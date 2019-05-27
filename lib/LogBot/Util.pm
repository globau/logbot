package LogBot::Util;
use local::lib;
use v5.10;
use strict;
use warnings;

BEGIN { $ENV{TZ} = 'UTC' }

our @EXPORT_OK = qw(
    logbot_init
    nick_is_bot
    normalise_channel source_to_nick
    slurp spurt touch file_time
    squash_error
    date_string_to_ymd timestamp time_to_ymd time_to_datestr time_to_datetimestr ymd_to_time
    path_for file_for
    event_to_string event_to_short_string
    commify pretty_size time_ago round plural
    run
);
use parent 'Exporter';

use Config qw ( %Config );
use Data::Dumper qw( Dumper );
use Date::Parse qw( str2time );
use DateTime ();
use File::Basename qw( basename );
use File::Path qw( make_path );
use List::Util qw( any );
use POSIX qw( WEXITSTATUS WIFEXITED WIFSIGNALED WTERMSIG ceil floor );
use Readonly;
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

sub source_to_nick {
    my ($source) = @_;
    if ($source =~ /^([^!]+)!/) {
        return $1;
    } else {
        return $source;
    }
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

sub date_string_to_ymd {
    my ($value) = @_;
    my $time = str2time($value, 'UTC') // return undef;
    return DateTime->from_epoch(epoch => $time)->truncate(to => 'day')->ymd('-');
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
    while ($ret = $fh->sysread(my $buffer, 131_072, 0)) {
        $content .= $buffer;
    }
    die "read $file: $!\n" unless defined $ret;
    close($fh) or die "close $file: $!\n";
    return $content;
}

sub spurt {
    my ($file, $content) = @_;
    open(my $fh, '>', $file) or die "create $file: $!\n";
    ($fh->syswrite($content) // -1) == length($content)
        or die "write $file: $!\n";
    close($fh) or die "write $file: $!\n";
}

sub touch {
    my ($file) = @_;
    if (-e $file) {
        utime(undef, undef, $file) or die "touch $file: $!\n";
    } else {
        open(my $fh, '>', $file) or die "create $file: $!\n";
        close($fh) or die "close $file: $!\n";
    }
}

sub file_time {
    my ($file) = @_;
    return -e $file ? (stat($file))[9] : undef;
}

sub file_for {
    my ($config, $type, @params) = @_;

    if ($type eq 'store') {
        return path_for($config, 'store') . '/logs.sqlite';

    } elsif ($type eq 'meta') {
        my ($channel, $filename) = @params;
        return path_for($config, 'meta', $channel) . '/' . $filename . '.json';

    } elsif ($type eq 'pid') {
        my ($executable) = @params;
        return $config->{_derived}->{root} . '/' . $executable . '.pid';

    } elsif ($type eq 'connected') {
        return path_for($config, 'store') . '/connected';

    } elsif ($type eq 'topics_lastmod') {
        return path_for($config, 'store') . '/topics.lastmod';

    } else {
        die $type;
    }
}

sub path_for {
    my ($config, $type, @params) = @_;

    if ($type eq 'queue') {
        return $config->{_derived}->{root} . '/queue';

    } elsif ($type eq 'meta') {
        my ($channel) = @params;
        my $path = $config->{_derived}->{root} . '/meta';
        if ($channel) {
            $channel =~ s/^#//;
            $path .= '/' . $channel;
        }
        make_path($path) unless -d $path;
        return $path;

    } elsif ($type eq 'store') {
        my $path = $config->{_derived}->{root};
        make_path($path) unless -d $path;
        return $path;

    } else {
        die $type;
    }
}

sub event_to_string {
    my ($event) = @_;

    my $time = DateTime->from_epoch(epoch => $event->{time})->iso8601();
    if ($event->{type} == 0) {
        return $time . ' ' . $event->{channel} . ' <' . $event->{nick} . '> ' . $event->{text};
    } elsif ($event->{type} == 1) {
        return $time . ' ' . $event->{channel} . ' * ' . $event->{nick} . ' ' . $event->{text};
    } elsif ($event->{type} == 2) {
        return $time . ' ' . $event->{channel} . ' -' . $event->{nick} . '- ' . $event->{text};
    } elsif ($event->{type} == 3) {
        return $time . ' ' . $event->{channel} . ' :topic: ' . $event->{text};
    } else {
        die 'unsupported event: ' . Dumper($event);
    }
}

sub event_to_short_string {
    my ($event) = @_;

    my $time = DateTime->from_epoch(epoch => $event->{time})->format_cldr('HH:mm:ss');
    if ($event->{type} == 0) {
        return $time . ' <' . $event->{nick} . '> ' . $event->{text};
    } elsif ($event->{type} == 1) {
        return $time . ' * ' . $event->{nick} . ' ' . $event->{text};
    } elsif ($event->{type} == 2) {
        return $time . ' -' . $event->{nick} . '- ' . $event->{text};
    } else {
        die 'unsupported event: ' . Dumper($event);
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
    my @base = qw( b k m g );
    my $base = 0;
    while ($bytes / 1024 >= 1) {
        $base++;
        $bytes = $bytes / 1024;
    }
    $precision = 0 if $base == 0;
    $bytes = sprintf("%.${precision}f", $bytes);
    return $bytes . $base[$base];
}

Readonly::Scalar my $ROUND_HALF => 0.50000000000008;

sub round {
    my ($value) = @_;
    return $value >= 0 ? floor($value + $ROUND_HALF) : ceil($value - $ROUND_HALF);
}

sub time_ago {
    my ($ss, $term) = @_;
    my $mm = round($ss / 60);
    my $hh = round($mm / 60);
    my $dd = round($hh / 24);
    my $mo = round($dd / 30);
    my $yy = round($mo / 12);
    $term //= 'ago';

    return 'just now'                if $ss < 10;
    return $ss . ' seconds ' . $term if $ss < 45;
    return 'a minute ' . $term       if $ss < 90;
    return $mm . ' minutes ' . $term if $mm < 45;
    return 'an hour ' . $term        if $mm < 90;
    return $hh . ' hours ' . $term   if $hh < 24;
    return 'a day ' . $term          if $hh < 36;
    return $dd . ' days ' . $term    if $dd < 30;
    return 'a month ' . $term        if $dd < 45;
    return $mo . ' months ' . $term  if $mo < 12;
    return 'a year ' . $term         if $mo < 18;
    return $yy . ' years ' . $term;
}

sub plural {
    my ($count, $object, $suffix) = @_;
    $suffix //= 's';
    return commify($count) . ' ' . $object . ($count == 1 ? '' : $suffix);
}

sub run {
    my @command = @_;
    my $exec    = shift @command;
    system($exec, @command);
    my $error = $?;
    die sprintf(qq#"%s" failed to start: "%s"\n#, $exec, $!) if $error == -1;
    if (WIFEXITED($error)) {
        my $exit_val = WEXITSTATUS($error);
        return if $exit_val == 0;
        print chr(7);
    } elsif (WIFSIGNALED($error)) {
        my $signal_no   = WTERMSIG($error);
        my @sig_names   = split(' ', $Config{sig_name});
        my $signal_name = $sig_names[$signal_no] // 'UNKNOWN';
        die sprintf(qq#"%s" died to signal "%s" (%d)\n#, basename($exec), $signal_name, $signal_no);
    }
}

1;
