package LogBot::Web::Search;
use local::lib;
use v5.10;
use strict;
use warnings;

use DateTime ();
use List::Util qw( any );
use LogBot::Database qw( dbh execute_with_timeout like_value replace_sql_placeholders );
use LogBot::Util qw( date_string_to_ymd normalise_channel time_to_ymd ymd_to_time );
use LogBot::Web::Util qw( preprocess_event url_for_channel );
use Mojo::Util qw( trim );
use Readonly;
use Text::ParseWords qw( quotewords );
use Time::HiRes ();
use Try::Tiny qw( catch try );

Readonly::Scalar my $SEARCH_FTS_LIMIT => 100_000;
Readonly::Scalar my $SEARCH_LIMIT     => 200;

sub render {
    my ($c, $q) = @_;
    my $config = $c->stash('config');

    my $today = DateTime->today()->epoch();
    $q = trim($q);

    # searching for a channel name redirects to the log
    if ($q =~ /^(#\S+)$/) {
        return $c->redirect_to(url_for_channel(channel => normalise_channel($1)));
    }

    my $ch = $c->param('ch') // '';
    if ($ch ne '') {
        $ch = normalise_channel($ch);
        $ch = '' unless any { $_ eq $ch } keys %{ $config->{channels} };
    }

    # searching for a ymd date redirects to that date
    if ($ch ne '' && $q =~ /^(\d\d\d\d)-?(\d\d)-?(\d\d)$/) {
        return $c->redirect_to(url_for_channel(channel => $ch, date => $1 . $2 . $3));
    }

    my $n = trim($c->param('n') // '');
    if ($q =~ s/<([^>]+)>\s*//) {
        $n = $1;
    }
    $n =~ s/(?:^<|>$)//g;

    my $last_c = $c->cookie('last-c') // '';
    if ($last_c ne '') {
        $last_c = normalise_channel($last_c);
        $last_c = '' if any { $_ eq $last_c } @{ $config->{_derived}->{hidden_channels} };
    }

    $c->stash(
        page => 'search',

        q   => $q,                                  # query
        ch  => $ch,                                 # channel
        chs => $c->every_param('chs'),              # multi-channel
        w   => $c->param('w') // 'r',               # when
        f   => date_string_to_ymd($c->param('f')),  # when from
        t   => date_string_to_ymd($c->param('t')),  # when to
        n   => $n,                                  # who
        i   => $c->param('i') // '',                # ignore bots
        ft  => $c->param('ft') // 'y',              # full-text

        last_c      => $last_c,
        debug       => '',
        logs        => undef,
        last_date   => undef,
        log_count   => 0,
        limited     => 0,
        searched    => 0,
        nick_hashes => [],
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

            # remove escaped quotes
            $quoted_q =~ s/[\\"]"//g;

            # fix unbalanced quotes
            my $quote_count = $quoted_q =~ tr/"/"/;
            $quoted_q .= '"' if $quote_count && ($quote_count % 2);

            # quotewords doesn't cope well with trailing \
            $quoted_q .= '\\' if $quoted_q =~ /\\$/;

            # wrap words in ", honouring user-supplied word groups
            $quoted_q = join(' ', map { '"' . $_ . '"' } quotewords('\s+', 0, $quoted_q));

            my $count;
            try {
                $count =
                    $dbh->selectrow_array('SELECT COUNT(*) FROM logs_fts WHERE logs_fts MATCH ?', undef, $quoted_q);
            }
            catch {
                # an error here means that fts failed somehow (there's some odd
                # syntax).  log so we can investigate later, and drop back to
                # substring.
                $c->app->log->error($_);
                $count = -1;
            };

            # fts is _fast_, however if it returns a massive number of rows,
            # sqlite can be slow at ordering.  if there are more than an
            # arbitrary amount of hits, switch to a substring search, which
            # will execute much faster.
            if ($count == -1 || $count > $SEARCH_FTS_LIMIT) {
                my ($condition, $value) = like_value(text => $q);
                push @where,  $condition;
                push @values, $value;

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
            my ($condition, $value) = like_value(text => $q);
            push @where,  $condition;
            push @values, $value;
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
    if ($c->stash('w') eq 'c' && !($c->stash('f') || $c->stash('t'))) {
        $c->stash('w', 'r');
    }

    if ($c->stash('w') eq 'r') {
        my $date = DateTime->today();
        push @where, 'time >= ' . $date->subtract(months => 3)->epoch;

    } elsif ($c->stash('w') eq 'c') {
        my $from_time = ymd_to_time($c->stash('f')) // $today;
        my $to_time   = ymd_to_time($c->stash('t')) // $today;

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

    # exclude hidden channels
    if (@{ $config->{_derived}->{hidden_channels} }) {
        push @where,
            'NOT(channel IN (' . join(',', map { $dbh->quote($_) } @{ $config->{_derived}->{hidden_channels} }) . '))';
    }

    # build sql

    #<<<
    my $sql =
        "SELECT COALESCE(old_id, id) AS id, time, channel, nick, type, text\n" .
        "FROM logs\n" .
        'WHERE (' . join(")\nAND (", @where) . ")\n" .
        "ORDER BY time DESC\n" .
        'LIMIT ' . ($SEARCH_LIMIT + 1) . "\n";
    #>>>

    # execute
    my $start_time = Time::HiRes::time();
    my $logs       = execute_with_timeout($dbh, $sql, \@values, 10);
    my $end_time   = Time::HiRes::time();

    # debug sql query
    if ($c->param('debug')) {
        my $debug = replace_sql_placeholders($dbh, $sql, \@values) . "\n";
        foreach my $row (@{ $dbh->selectall_arrayref("EXPLAIN QUERY PLAN $debug") }) {
            $debug .= join(' ', @{$row}) . "\n";
        }
        $debug .= sprintf("\n%.2fs", $end_time - $start_time);
        $c->stash(debug => $debug);
    }

    unless (defined $logs) {
        $c->stash(error => 'Search took too long to process and has been cancelled.');
        return $c->render('search');
    }

    # deal with hitting search limit
    my $limited = 0;
    if (scalar(@{$logs}) == $SEARCH_LIMIT + 1) {
        pop @{$logs};
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
    my $nick_hashes     = {};
    my ($date_channels, $channel_events);
    foreach my $event (@{$logs}) {
        my $date    = time_to_ymd($event->{time});
        my $channel = $event->{channel};

        if ($current_date ne $date) {
            $current_date    = $date;
            $current_channel = '';
            $date_channels   = {};
            push @collated, { date => $event->{time}, channels => $date_channels };
        }

        if ($current_channel ne $channel) {
            $current_channel = $channel;
            $channel_events = $date_channels->{$channel} //= [];
        }

        preprocess_event($config, $event, $nick_hashes);
        push @{$channel_events}, $event;
    }

    foreach my $date_block (@collated) {
        foreach my $channel (keys %{ $date_block->{channels} }) {
            $date_block->{channels}->{$channel} = [reverse @{ $date_block->{channels}->{$channel} }];
        }
    }

    $c->stash(
        logs        => \@collated,
        limit       => $SEARCH_LIMIT,
        limited     => $limited,
        log_count   => scalar(@{$logs}),
        nick_hashes => [keys %{$nick_hashes}],
        searched    => 1,
    );

    $c->render('search');
}

1;
