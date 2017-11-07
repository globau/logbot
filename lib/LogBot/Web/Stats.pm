package LogBot::Web::Stats;
use local::lib;
use v5.10;
use strict;
use warnings;

use DateTime ();
use JSON::XS qw( decode_json );
use LogBot::Database qw( dbh );
use LogBot::Util qw( commify file_for pretty_size slurp time_to_datetimestr );
use LogBot::Web::Util qw( irc_host );
use Time::Duration qw( ago );

sub render {
    my ($c, $params) = @_;
    my $config = $c->stash('config');

    if (my $error = $params->{error}) {
        $c->stash(
            channel => '',
            error   => $error,
        );
    }

    $c->stash(
        is_stats => 1,
        url      => irc_host($config, channel => $c->stash('channel'), url => 1),
        now      => time_to_datetimestr(DateTime->now()->epoch),
    );

    return $c->render('stats');
}

sub event_time_to_str {
    my ($time) = @_;
    return ('no events', '-') unless $time;
    return (time_to_datetimestr(int($time)), ago(time() - $time));
}

sub meta {
    my ($c, $channel) = @_;
    my $config = $c->stash('config');

    my $dbh = dbh($config, cached => 1);

    my ($last_time, $last_ago, $event_count);
    if ($channel) {
        $last_time =
            $dbh->selectrow_array("SELECT time FROM logs WHERE channel = ? ORDER BY time DESC LIMIT 1", undef,
            $channel);
        $event_count = $dbh->selectrow_array("SELECT COUNT(*) FROM logs WHERE channel = ?", undef, $channel);
    } else {
        $last_time   = $dbh->selectrow_array("SELECT time FROM logs ORDER BY time DESC LIMIT 1");
        $event_count = $dbh->selectrow_array("SELECT COUNT(*) FROM logs");
    }

    ($last_time, $last_ago) = event_time_to_str($last_time);

    my ($first_time, $first_ago, $active_events, $active_nicks);
    my $meta_file = file_for($config, 'meta', $channel, 'meta');
    if (-e $meta_file) {
        my $meta = decode_json(slurp($meta_file));

        ($first_time, $first_ago) = event_time_to_str($meta->{first_time});

        $active_events =
              $meta->{active_events_days}
            ? $meta->{active_events} / $meta->{active_events_days}
            : 0;
        if (sprintf('%.1f', $active_events) eq '0.0') {
            $active_events = '0';
        } elsif ($active_events < 1) {
            $active_events = sprintf('%.1f', $active_events);
        } else {
            $active_events = sprintf('%.0f', $active_events);
        }

        $active_nicks = $meta->{active_nicks};

    } else {
        $first_time    = '-';
        $first_ago     = '-';
        $active_events = '0';
        $active_nicks  = '0';
    }

    return {
        first_time    => $first_time,
        first_ago     => $first_ago,
        last_time     => $last_time,
        last_ago      => $last_ago,
        event_count   => commify($event_count),
        active_events => commify($active_events) . ' event' . ($active_events == 1 ? '' : 's') . '/day',
        active_nicks  => commify($active_nicks) . ' active user' . ($active_nicks == 1 ? '' : 's'),
    };
}

sub hours {
    my ($c, $channel) = @_;
    my $config = $c->stash('config');

    my $file = file_for($config, 'meta', $channel, 'hours');
    return -e $file ? slurp($file) : slurp(file_for($config, 'meta', '_empty', 'hours'));
}

sub nicks {
    my ($c, $channel) = @_;
    my $config = $c->stash('config');

    my $file = file_for($config, 'meta', $channel, 'nicks');
    return -e $file ? slurp($file) : slurp(file_for($config, 'meta', '_empty', 'nicks'));
}

1;
