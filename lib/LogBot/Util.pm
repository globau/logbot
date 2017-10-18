package LogBot::Util;
use local::lib;
use v5.10;
use strict;
use warnings;

BEGIN { $ENV{TZ} = 'UTC' }

our @EXPORT_OK = qw(
    logbot_init
    nick_hash nick_is_bot
    normalise_channel
    slurp spurt
    squash_error
    timestamp time_to_ymd time_to_datestr time_to_datetimestr ymd_to_time
    path_for file_for
    event_to_string event_to_short_string
    commify pretty_size
);
use parent 'Exporter';

use Data::Dumper qw( Dumper );
use DateTime ();
use File::Basename qw( basename dirname );
use File::Path qw( make_path );
use FindBin qw( $RealBin );
use List::Util qw( any );
use Time::Local qw( timelocal );

my $pid_file;

END {
    unlink($pid_file) if $pid_file;
}

sub logbot_init {
    my ($config, %params) = @_;

    $Data::Dumper::Terse    = 1;
    $Data::Dumper::Sortkeys = 1;

    my $name = $params{name} // basename($0);
    $0 = $name;
    $pid_file = file_for($config, 'pid', $0);
    spurt($pid_file, "$$\n");
    $0 .= ' (' . $config->{name} . ')';

    unless ($params{quiet}) {
        say timestamp(), ' -- starting ', $0;
    }
}

sub nick_hash {
    my ($nick) = @_;
    $nick = lc($nick);
    $nick =~ s/[`_]+$//;
    $nick =~ s/\|.*$//;
    my $hash = 0;
    for (my $i = 0; $i < length($nick); $i++) {
        $hash = ord(substr($nick, $i, 1)) + ($hash << 6) + ($hash << 16) - $hash;
    }
    return $hash;
}

sub nick_is_bot {
    my ($config, $nick) = @_;
    $nick = lc($nick);
    return any { $_ eq $nick } @{ $config->{bots} };
}

sub normalise_channel {
    my ($channel) = @_;
    $channel = '#' . $channel unless substr($channel, 0, 1) eq '#';
    return lc($channel);
}

sub timestamp {
    my @now = gmtime();
    return sprintf('[%04d-%02d-%02d %02d:%02d:%02d]', $now[5] + 1900, $now[4] + 1, $now[3], $now[2], $now[1], $now[0]);
}

sub time_to_ymd {
    my ($time, $sep) = @_;
    my ($yy, $mm, $dd) = (localtime($time))[5, 4, 3];
    my $fmt = $sep ? '%d' . $sep . '%02d' . $sep . '%02d' : '%d%02d%02d';
    return sprintf($fmt, $yy + 1900, $mm + 1, $dd);
}

my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

sub time_to_datestr {
    my ($time) = @_;
    my ($yy, $mm, $dd) = (localtime($time))[5, 4, 3];
    return sprintf('%d %s %d', $dd, $months[$mm], $yy + 1900);
}

sub time_to_datetimestr {
    my ($time) = @_;
    my ($yy, $mm, $dd, $hh, $nn) = (localtime($time))[5, 4, 3, 2, 1];
    return sprintf('%d %s %d %02d:%02d', $dd, $months[$mm], $yy + 1900, $hh, $nn);
}

sub ymd_to_time {
    my ($ymd) = @_;
    return unless defined($ymd) && $ymd ne '';
    $ymd =~ tr/-//d;
    my ($yyyy, $mm, $dd) = (substr($ymd, 0, 4), substr($ymd, 4, 2), substr($ymd, 6, 2));
    my $time = eval { timelocal(0, 0, 0, $dd, $mm - 1, $yyyy - 1900) };
    return $time;
}

sub squash_error {
    my ($s) = @_;
    $s =~ s/[\r\n]+/ /g;
    $s =~ s/^(.+?) at \S+ line \d+.+/$1/;
    $s =~ s/(^\s+|\s+$)//g;
    return $s;
}

sub slurp {
    my ($file) = @_;
    open(my $fh, '<', $file) or die "open $file: $!\n";
    my $ret = my $content = '';
    while ($ret = $fh->sysread(my $buffer, 131072, 0)) {
        $content .= $buffer;
    }
    die "read $file: $!\n" unless defined $ret;
    return $content;
}

sub spurt {
    my ($file, $content) = @_;
    open(my $fh, '>', $file) or die "create $file: $!\n";
    ($fh->syswrite($content) // -1) == length($content)
        or die "write $file: $!\n";
}

sub file_for {
    my ($config, $type, @params) = @_;

    if ($type eq 'db') {
        return path_for($config, 'db') . '/logs.sqlite';

    } elsif ($type eq 'meta') {
        my ($channel, $filename) = @params;
        return path_for($config, 'meta', $channel) . '/' . $filename . '.json';

    } elsif ($type eq 'pid') {
        my ($executable) = @params;
        return $config->{_internal}->{root} . '/' . $executable . '.pid';

    } else {
        die $type;
    }
}

sub path_for {
    my ($config, $type, @params) = @_;

    if ($type eq 'queue') {
        return $config->{_internal}->{root} . '/queue';

    } elsif ($type eq 'meta') {
        my ($channel) = @params;
        $channel =~ s/^#//;
        my $path = $config->{_internal}->{root} . '/meta/' . $channel;
        make_path($path) unless -d $path;
        return $path;

    } elsif ($type eq 'db') {
        my $path = $config->{_internal}->{root};
        make_path($path) unless -d $path;
        return $path;

    } else {
        die $type;
    }
}

sub event_to_string {
    my ($event) = @_;

    my $time = DateTime->from_epoch(epoch => $event->{time})->iso8601();
    if ($event->{type} eq 0) {
        return $time . ' ' . $event->{channel} . ' <' . $event->{nick} . '> ' . $event->{text};
    } elsif ($event->{type} eq 1) {
        return $time . ' ' . $event->{channel} . ' * ' . $event->{nick} . ' ' . $event->{text};
    } elsif ($event->{type} eq 2) {
        return $time . ' ' . $event->{channel} . ' -' . $event->{nick} . '- ' . $event->{text};
    } else {
        die "unsupported event: " . Dumper($event);
    }
}

sub event_to_short_string {
    my ($event) = @_;

    my $time = DateTime->from_epoch(epoch => $event->{time})->format_cldr('hh:mm:ss');
    if ($event->{type} eq 0) {
        return $time . ' <' . $event->{nick} . '> ' . $event->{text};
    } elsif ($event->{type} eq 1) {
        return $time . ' * ' . $event->{nick} . ' ' . $event->{text};
    } elsif ($event->{type} eq 2) {
        return $time . ' -' . $event->{nick} . '- ' . $event->{text};
    } else {
        die "unsupported event: " . Dumper($event);
    }
}

sub commify {
    my ($n) = @_;
    1 while $n =~ s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $n;
}

sub pretty_size {
    my ($bytes, $precision) = @_;
    $bytes     //= 0;
    $precision //= 1;
    my @base = ('b', 'k', 'm', 'g');
    my $base = 0;
    while ($bytes / 1024 >= 1) {
        $base++;
        $bytes = $bytes / 1024;
    }
    $precision = 0 if $base == 0;
    $bytes = sprintf("%.${precision}f", $bytes);
    return $bytes . $base[$base];
}

1;
