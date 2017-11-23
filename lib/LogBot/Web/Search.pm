package LogBot::Web::Search;
use local::lib;
use v5.10;
use strict;
use warnings;

use Date::Parse qw( str2time );
use DateTime ();
use Encode qw( decode );
use List::Util qw( any );
use LogBot::Database qw( dbh execute_with_timeout like_value replace_sql_placeholders );
use LogBot::Util qw( nick_hash nick_is_bot normalise_channel time_to_ymd ymd_to_time );
use LogBot::Web::Channel ();
use LogBot::Web::Util qw( linkify url_for_channel );
use Mojo::Util qw( trim );
use Text::ParseWords qw( quotewords );
use Time::HiRes ();

use constant SEARCH_FTS_LIMIT => 100_000;
use constant SEARCH_LIMIT     => 200;

sub render {
    my ($c, $q) = @_;
    my $config = $c->stash('config');

    my $today = DateTime->now->truncate(to => 'day');
    $q = trim($q);

    # searching for a channel name redirects to the log
    if ($q =~ /^(#\S+)$/) {
        return $c->redirect_to(url_for_channel(channel => normalise_channel($1)));
    }

    my $ch = $c->param('ch') // '';
    $ch = normalise_channel($ch) if $ch ne '';

    # searching for a ymd date redirects to that date
    if ($ch ne '' && $q =~ /^(\d\d\d\d)-?(\d\d)-?(\d\d)$/) {
        return $c->redirect_to(url_for_channel(channel => $ch, date => $1 . $2 . $3));
    }

    my $n = trim($c->param('n') // '');
    $n = $1 if $q =~ s/<([^>]+)>\s*//;
    $n =~ s/(?:^<|>$)//g;

    $c->stash(
        is_search => 1,

        q   => $q,                                  # query
        ch  => $ch,                                 # channel
        chs => $c->every_param('chs'),              # multi-channel
        w   => $c->param('w') // 'r',               # when
        f   => date_string_to_ymd($c->param('f')),  # when from
        t   => date_string_to_ymd($c->param('t')),  # when to
        n   => $n,                                  # who
        i   => $c->param('i') // '',                # ignore bots
        ft  => $c->param('ft') // 'y',              # full-text

        debug     => '',
        logs      => undef,
        last_date => undef,
        log_count => 0,
        limited   => 0,
        searched  => 0,
    );

    return $c->render('search') if $q eq '' && $n eq '';

    # init
    my $dbh = dbh($config, cached => 1);
    my @bots = @{ $config->{bots} };

    # build query
    my @where;
    my @values;

    # text
    if ($q ne '') {
        if ($c->stash('ft') eq 'y') {
            my $quoted_q = $q;

            # always treat apostrophe as literial
            $quoted_q =~ s/'/\\'/g;

            # fix unbalanced quotes
            my $quote_count = $quoted_q =~ tr/"/"/;
            $quoted_q .= '"' if $quote_count && ($quote_count % 2);

            # wrap words in ", honouring user-supplied word groups
            $quoted_q = join(' ', map { '"' . $_ . '"' } quotewords('\s+', 0, $quoted_q));

            my $count = $dbh->selectrow_array('SELECT COUNT(*) FROM logs_fts WHERE logs_fts MATCH ?', undef, $quoted_q);

            # fts is _fast_, however if it returns a massive number of rows,
            # sqlite can be slow at ordering.  if there are more than an
            # arbitrary amount of hits, switch to a substring search, which
            # will execute much faster.
            if ($count > SEARCH_FTS_LIMIT) {
                push @where,  'text LIKE ?';
                push @values, like_value($q);

            } else {
                #<<<
                push @where, 'logs.id IN (' .
                    'SELECT logs_fts.rowid ' .
                    'FROM logs_fts ' .
                    'WHERE logs_fts MATCH ? ' .
                    'ORDER BY time)';
                #>>>
                push @values, $quoted_q;
            }

        } else {
            push @where,  'text LIKE ?';
            push @values, like_value($q);
        }
    }

    # channel
    if ($c->stash('ch')) {
        push @where,  'channel = ?';
        push @values, $c->stash('ch');

    } elsif (@{ $c->stash('chs') }) {
        push @where, 'channel IN (' . join(',', map { $dbh->quote($_) } @{ $c->stash('chs') }) . ')';
    }

    # when
    if ($c->stash('w') eq 'c' && !($c->param('f') || $c->param('t'))) {
        $c->stash('w', 'r');
    }

    if ($c->stash('w') eq 'r') {
        my $date = DateTime->now();
        push @where, 'time >= ' . $today->subtract(months => 3)->epoch;

    } elsif ($c->stash('w') eq 'c') {
        my $today     = DateTime->today->epoch();
        my $from_time = ymd_to_time($c->param('f')) // $today;
        my $to_time   = ymd_to_time($c->param('t')) // $today;

        if ($to_time < $from_time) {
            ($from_time, $to_time) = ($to_time, $from_time);
        }

        $c->stash(
            f => time_to_ymd($from_time, '-'),
            t => time_to_ymd($to_time,   '-'),
        );

        push @where, 'time BETWEEN ' . $from_time . ' AND ' . $to_time;
    }

    # who
    if ($n ne '') {
        push @where,  'nick = ? COLLATE NOCASE';
        push @values, $n;
    }

    # bots
    if ($c->stash('i') && @bots) {
        push @where, 'NOT(nick COLLATE NOCASE IN (' . join(',', map { $dbh->quote($_) } @bots) . '))';
    }

    # build sql

    #<<<
    my $sql =
        "SELECT COALESCE(old_id, id) AS id, time, channel, nick, type, text\n" .
        "FROM logs\n" .
        "WHERE (" . join(")\nAND (", @where) . ")\n" .
        "ORDER BY time DESC\n" .
        "LIMIT " . (SEARCH_LIMIT + 1) . "\n";
    #>>>

    # execute
    my $start_time = Time::HiRes::time();
    my $logs       = execute_with_timeout($dbh, $sql, \@values, 10);
    my $end_time   = Time::HiRes::time();

    # debug sql query
    if ($c->param('debug')) {
        my $debug = replace_sql_placeholders($dbh, $sql, \@values) . "\n";
        foreach my $row (@{ $dbh->selectall_arrayref("EXPLAIN QUERY PLAN $debug") }) {
            $debug .= join(' ', @$row) . "\n";
        }
        $debug .= sprintf("\n%.2fs", $end_time - $start_time);
        $c->stash(debug => $debug);
    }

    unless (defined $logs) {
        $c->stash(error => "Search took too long to process and has been cancelled.");
        return $c->render('search');
    }

    # deal with hitting search limit
    my $limited = 0;
    if (scalar(@$logs) == SEARCH_LIMIT + 1) {
        pop @$logs;
        $limited = 1;
    }

    # [
    #   {
    #       date => $time,
    #       channels => {
    #           $channel => [ $event, .. ],
    #           ...
    #       },
    #   },
    # ]

    # collate events by date desc, then channel asc, then time asc
    my @collated;
    my $current_channel = '';
    my $current_date    = '';
    my ($date_channels, $channel_events);
    foreach my $event (@$logs) {
        my $date    = time_to_ymd($event->{time});
        my $channel = $event->{channel};

        if ($current_date ne $date) {
            $current_date    = $date;
            $current_channel = '';
            $date_channels   = {};
            push @collated, { date => $event->{time}, channels => $date_channels };
        }

        if ($current_channel ne $channel) {
            $current_channel           = $channel;
            $channel_events            = [];
            $date_channels->{$channel} = $channel_events;
        }

        push @$channel_events, $event;

        $event->{bot} = nick_is_bot($config, $event->{nick});
        $event->{hash} = $event->{bot} ? '0' : nick_hash($event->{nick});
        $event->{hhss} = sprintf('%02d:%02d', (localtime($event->{time}))[2, 1]);
        $event->{text} = linkify(decode('UTF-8', $event->{text}));
    }

    foreach my $date_block (@collated) {
        foreach my $channel (keys %{ $date_block->{channels} }) {
            $date_block->{channels}->{$channel} = [reverse @{ $date_block->{channels}->{$channel} }];
        }
    }

    $c->stash(
        logs      => \@collated,
        limit     => SEARCH_LIMIT,
        limited   => $limited,
        log_count => scalar(@$logs),
        searched  => 1,
    );

    $c->render('search');
}

sub date_string_to_ymd {
    my ($value) = @_;
    my $time = str2time($value, 'UTC') // return undef;
    return DateTime->from_epoch(epoch => $time)->truncate(to => 'day')->ymd('-');
}

1;
