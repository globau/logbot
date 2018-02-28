package LogBot::Web::Channel;
use local::lib;
use v5.10;
use strict;
use warnings;

use DateTime ();
use Encode qw( decode );
use List::Util qw( any );
use LogBot::Database qw( dbh execute_with_timeout );
use LogBot::Util qw( event_to_short_string nick_is_bot normalise_channel time_to_ymd );
use LogBot::Web::Util qw( linkify nick_hash );

sub _get_logs {
    my ($c, $dbh) = @_;

    my $start_time = $c->stash('date')->epoch;
    my $end_time = $c->stash('date')->clone->add(days => 1)->epoch;

    ## no critic (ProhibitInterpolationOfLiterals)
    #<<<
    my $sql =
        "SELECT COALESCE(old_id, id) AS id, time, channel, nick, type, text\n" .
        "FROM logs\n" .
        "WHERE (channel = ?) AND (time >= " . $start_time . ") AND (time < " . $end_time . ")\n" .
        "ORDER BY time ASC";
    #>>>
    ## use critic

    my $logs = execute_with_timeout($dbh, $sql, [$c->stash('channel')], 5);
    unless (defined $logs) {
        $c->stash(error => 'Request took too long to process and has been cancelled.',);
        $c->render('channel');
        return undef;
    }

    return ($logs, $sql);
}

sub logs {
    my ($c, $params) = @_;
    my $config = $c->stash('config');

    if (my $error = $params->{error}) {
        $c->stash(
            channel => '',
            error   => $error,
        );
    }
    return $c->render('index') unless $c->stash('channel');

    $c->stash(
        logs      => undef,
        last_date => undef,
        skip_prev => undef,
        skip_next => undef,
    );

    my $dbh = dbh($config, cached => 1);
    my ($logs, $sql) = _get_logs($c, $dbh);
    return unless defined($logs);

    # process each event
    my $bot_event_count = 0;
    foreach my $event (@{$logs}) {
        $event->{bot} = nick_is_bot($config, $event->{nick});
        $event->{hash} = $event->{bot} ? '0' : nick_hash($event->{nick});
        $event->{hhss} = sprintf('%02d:%02d', (localtime($event->{time}))[2, 1]);
        $event->{text} = linkify(decode('UTF-8', $event->{text}));
        $bot_event_count++ if $event->{bot};
    }

    # calc last message date for channel
    if (@{$logs}) {
        $c->stash(last_date => DateTime->from_epoch(epoch => $logs->[-1]->{time}));

    } else {
        my $time = $c->stash('date')->epoch;

        my $skip_prev_time =
            $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? AND time < ? ORDER BY time DESC LIMIT 1',
            undef, $c->stash('channel'), $time);
        if ($skip_prev_time) {
            $c->stash(skip_prev => DateTime->from_epoch(epoch => $skip_prev_time)->truncate(to => 'day'));
        }

        my $skip_next_time =
            $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? AND time > ? ORDER BY time ASC LIMIT 1',
            undef, $c->stash('channel'), $time);
        if ($skip_next_time) {
            $c->stash(skip_next => DateTime->from_epoch(epoch => $skip_next_time)->truncate(to => 'day'));
        }
    }

    $c->stash(
        logs            => $logs,
        event_count     => scalar(@{$logs}),
        bot_event_count => $bot_event_count,
    );

    $c->render('channel');
}

sub raw {
    my ($c, $params) = @_;
    my $config = $c->stash('config');

    if (my $error = $params->{error}) {
        $c->stash(
            channel => '',
            error   => $error,
        );
    }
    return $c->render('index') unless $c->stash('channel');

    my $dbh = dbh($config, cached => 1);
    my ($logs) = _get_logs($c, $dbh);

    my @lines;
    foreach my $event (@{$logs}) {
        $event->{text} = decode('UTF-8', $event->{text});
        push @lines, event_to_short_string($event);
    }

    $c->render(text => join("\n", @lines) . "\n", format => 'txt', charset => 'utf-8');
}
1;
