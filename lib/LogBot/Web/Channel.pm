package LogBot::Web::Channel;
use local::lib;
use v5.10;
use strict;
use warnings;

use DateTime ();
use Encode qw( decode );
use LogBot::Database qw( dbh execute_with_timeout );
use LogBot::Util qw( event_to_short_string );
use LogBot::Web::Util qw( channel_from_param date_from_param munge_emails preprocess_event url_for_channel );

sub _get_logs {
    my ($c, $dbh, $channel, $date) = @_;

    my $start_time = $date->epoch;
    my $end_time = $date->clone->add(days => 1)->epoch;

    ## no critic (ProhibitInterpolationOfLiterals)
    #<<<
    my $sql =
        "SELECT COALESCE(old_id, id) AS id, time, channel, nick, type, text\n" .
        "FROM logs\n" .
        "WHERE (channel = ?) AND (time >= " . $start_time . ") AND (time < " . $end_time . ")\n" .
        "ORDER BY time ASC";
    #>>>
    ## use critic

    my $logs = execute_with_timeout($dbh, $sql, [$channel], 5);
    unless (defined $logs) {
        $c->stash(error => 'Request took too long to process and has been cancelled.',);
        $c->render('channel');
        return undef;
    }

    return ($logs, $sql);
}

sub render_logs {
    my ($c) = @_;
    my $config = $c->stash('config');

    my $channel = channel_from_param($c) // return;

    my $date = date_from_param($c);
    if (!defined $date) {
        return $c->redirect_to('/' . substr($channel, 1) . '/' . $c->stash('today')->ymd(''));
    }
    my $is_today = $date == $c->stash('today');
    my $time     = $date->epoch;

    my $dbh = dbh($config, cached => 1);
    my ($logs, $sql) = _get_logs($c, $dbh, $channel, $date);
    return unless defined($logs);

    # store last visited channel
    $c->cookie(
        'last-c' => $channel, {
            path    => '/',
            expires => time() + 60 * 60 * 24 * 365,
        }
    );

    # process each event
    my $bot_event_count = 0;
    my $nick_hashes     = {};
    foreach my $event (@{$logs}) {
        preprocess_event($config, $event, $nick_hashes);
        $bot_event_count++ if $event->{bot};
    }

    # calc navigation dates

    $c->stash(
        last_date => undef,
        skip_prev => undef,
        skip_next => undef,
    );

    if (@{$logs} && $is_today) {
        $c->stash(last_date => DateTime->from_epoch(epoch => $logs->[-1]->{time}));
    }

    my $skip_prev_time =
        $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? AND time < ? ORDER BY time DESC LIMIT 1',
        undef, $channel, $time);
    if ($skip_prev_time) {
        $c->stash(skip_prev => DateTime->from_epoch(epoch => $skip_prev_time)->truncate(to => 'day'));
    }

    my $skip_next_time =
        $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? AND time >= ? ORDER BY time ASC LIMIT 1',
        undef, $channel, $time + 60 * 60 * 24);
    if ($skip_next_time) {
        $c->stash(skip_next => DateTime->from_epoch(epoch => $skip_next_time)->truncate(to => 'day'));
    }

    $c->stash(
        channel         => $channel,
        date            => $date,
        page            => 'logs',
        is_today        => $is_today,
        logs            => $logs,
        event_count     => scalar(@{$logs}),
        bot_event_count => $bot_event_count,
        nick_hashes     => [keys %{$nick_hashes}],
    );

    $c->render('channel');
}

sub render_raw {
    my ($c) = @_;
    my $config = $c->stash('config');

    my $channel = channel_from_param($c) // return;

    my $date = date_from_param($c);
    if (!defined $date) {
        return $c->redirect_to('/' . substr($channel, 1) . '/' . $c->stash('today')->ymd(''));
    }

    my $dbh = dbh($config, cached => 1);
    my ($logs) = _get_logs($c, $dbh, $channel, $date);

    my @lines;
    foreach my $event (@{$logs}) {
        $event->{text} = munge_emails(decode('UTF-8', $event->{text}));
        push @lines, event_to_short_string($event);
    }

    $c->render(text => join("\n", @lines) . "\n", format => 'txt', charset => 'utf-8');
}

sub _get_link {
    my ($c) = @_;
    my $config = $c->stash('config');
    my $dbh = dbh($config, cached => 1);

    my $channel = channel_from_param($c) // return (404, 'Channel not logged');
    my $time    = $c->param('time')      // return (400, 'Bad or missing timestamp');
    my $nick    = $c->param('nick')      // return (400, 'Bad or missing nick');

    # search for entries +/- 5 seconds from the specified time
    # returns closest match
    ## no critic (ProhibitInterpolationOfLiterals)
    #<<<
    my $sql =
        "SELECT COALESCE(old_id, id) AS id\n" .
        "FROM logs\n" .
        "WHERE (channel = ?) " .
            "AND (time BETWEEN " . ($time - 5) . " AND " . ($time + 5) . ") ".
            "AND (nick = ? COLLATE NOCASE)\n" .
        "ORDER BY ABS(time - $time) ASC, time\n" .
        "LIMIT 1";
    #>>>
    ## use critic

    my $logs = execute_with_timeout($dbh, $sql, [$channel, $nick], 5);
    return (408, 'Request took too long to process and has been cancelled.') unless defined $logs;
    return (404, 'Entry not found') unless scalar @{$logs};
    return (
        302,
        url_for_channel(
            channel => $channel,
            date    => DateTime->from_epoch(epoch => $time),
            id      => $logs->[0]->{id},
        )
    );
}

sub redirect_to {
    my ($c) = @_;
    my ($status, $response) = _get_link($c);
    if ($status == 302) {
        $c->redirect_to($response);
    } else {
        $c->render(status => $status, text => $response, format => 'txt');
    }
}

1;
