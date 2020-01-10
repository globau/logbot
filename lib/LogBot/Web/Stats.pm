package LogBot::Web::Stats;
use local::lib;
use v5.10;
use strict;
use warnings;

use Cpanel::JSON::XS qw( decode_json );
use DateTime ();
use List::Util qw( uniq );
use LogBot::Database qw( dbh );
use LogBot::Util qw( commify file_for plural slurp time_to_datetimestr );
use LogBot::Web::Util qw( channel_from_param irc_host );
use Time::Duration qw( ago );

sub render {
    my ($c, %params) = @_;
    my $config = $c->stash('config');

    if ($params{require_channel}) {
        my $channel = channel_from_param($c) // return;
        $c->stash(channel => $channel);
    }

    $c->stash(
        page => 'stats',
        url  => irc_host($config, channel => $c->stash('channel'), url => 1),
        now  => time_to_datetimestr(DateTime->now()->epoch),
    );

    return $c->render('stats');
}

sub event_time_to_str {
    my ($time, $accuracy) = @_;
    return ('no events', '-') unless $time;
    return (time_to_datetimestr(int($time)), ago(time() - $time, $accuracy // 2));
}

sub render_meta {
    my ($c, %params) = @_;
    my $config = $c->stash('config');

    my $channel;
    if ($params{require_channel}) {
        $channel = channel_from_param($c) // return;
    }

    my $dbh = dbh($config, cached => 1);

    my ($last_time, $last_ago, $event_count);
    if ($channel) {
        $last_time =
            $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? ORDER BY time DESC LIMIT 1', undef,
            $channel);
        $event_count = $dbh->selectrow_array('SELECT COUNT(*) FROM logs WHERE channel = ?', undef, $channel);
    } else {
        $last_time = $dbh->selectrow_array('SELECT time FROM logs ORDER BY time DESC LIMIT 1');
    }

    ($last_time, $last_ago) = event_time_to_str($last_time, 1);

    my ($first_ago, $active_events, $active_nicks);
    my $meta_file = file_for($config, 'meta', $channel, 'meta');
    if (-e $meta_file) {
        my $meta = decode_json(slurp($meta_file));

        (undef, $first_ago) = event_time_to_str($meta->{first_time});

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

        $active_nicks = $meta->{active_nicks} // '0';

        $event_count //= $meta->{event_count};

    } else {
        $first_ago     = '-';
        $active_events = '0';
        $active_nicks  = '0';
        $event_count //= '0';
    }

    my $channels_in = scalar(grep { !($_->{archived} || $_->{blocked} || $_->{disabled}) } values %{$config->{channels}});
    my $archived = scalar(grep { $_->{archived} && !($_->{blocked} || $_->{disabled}) } values %{$config->{channels}});

    $c->render(
        json => {
            first_ago      => $first_ago,
            last_ago       => $last_ago,
            event_count    => commify($event_count),
            active_events  => plural($active_events, 'event') . '/day',
            active_nicks   => plural($active_nicks, 'active user'),
            channels_in    => 'Logging ' . plural($channels_in, 'channel'),
            channels_total => plural($archived, 'archived channel'),
        }
    );
}

sub render_hours {
    my ($c, %params) = @_;
    my $config = $c->stash('config');

    my $channel;
    if ($params{require_channel}) {
        $channel = channel_from_param($c) // return;
    }

    my $file = file_for($config, 'meta', $channel, 'hours');
    $c->render(
        text => -e $file ? slurp($file) : slurp(file_for($config, 'meta', '_empty', 'hours')),
        format => 'json',
    );
}

sub render_nicks {
    my ($c) = @_;
    my $config = $c->stash('config');

    my $channel = channel_from_param($c) // return;

    my $file = file_for($config, 'meta', $c->stash('channel'), 'nicks');
    my $data = decode_json(-e $file ? slurp($file) : slurp(file_for($config, 'meta', '_empty', 'nicks')));

    my @nick_hashes;
    foreach my $nick (@{$data}) {
        push @nick_hashes, $nick->{hash};
    }

    $c->stash(nicks => $data, nick_hashes => [uniq @nick_hashes]);
    $c->render('stats_nicks');
}

1;
