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

    my ($last_time, $last_ago) = event_time_to_str(
        $dbh->selectrow_array("SELECT time FROM logs WHERE channel = ? ORDER BY time DESC LIMIT 1", undef, $channel));
    my $event_count = commify($dbh->selectrow_array("SELECT COUNT(*) FROM logs WHERE channel = ?", undef, $channel));

    my ($first_time, $first_ago, $event_size, $activity);
    my $meta_file = file_for($config, 'meta', $channel, 'meta');
    if (-e $meta_file) {
        my $meta = decode_json(slurp($meta_file));

        ($first_time, $first_ago) = event_time_to_str($meta->{first_time});
        $event_size = pretty_size($meta->{event_size});

        $activity = $meta->{activity_count} / $meta->{activity_days};
        if (sprintf('%.1f', $activity) eq '0.0') {
            $activity = '0';
        } elsif ($activity < 1) {
            $activity = sprintf('%.1f', $activity);
        } else {
            $activity = sprintf('%.0f', $activity);
        }

    } else {
        $first_time = '-';
        $first_ago  = '-';
        $event_size = '0b';
        $activity   = '0';
    }

    return {
        first_time  => $first_time,
        first_ago   => $first_ago,
        last_time   => $last_time,
        last_ago    => $last_ago,
        event_count => $event_count,
        event_size  => $event_size,
        activity    => $activity . ' event' . ($activity == 1 ? '' : 's') . '/day (last 6 months)',
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
