package LogBot::Web::Colour;
use local::lib;
use v5.10;
use strict;
use warnings;

use Digest::xxHash qw( xxhash32 );
use List::Util qw( max min );
use Memoize qw( memoize );
use Memoize::ExpireLRU ();
use POSIX qw( ceil floor );

our @EXPORT_OK = qw(
    nick_hash nick_colour
);
use parent 'Exporter';

sub nick_hash {
    my ($nick) = @_;

    $nick = lc($nick);
    $nick =~ s/[`_]+$//;
    $nick =~ s/\|.*$//;

    return xxhash32($nick, 0);
}

sub nick_colour {
    my ($hash) = @_;
    $hash = $hash + 0;

    my @light_hsl =
        ($hash % 360, (20 + $hash % 80) / 100, (($hash % 360) >= 30 && ($hash % 360) <= 210 ? 30 : 50) / 100,);
    my @dark_hsl = darken(@light_hsl);

    return (hsl_to_rgb(@light_hsl), hsl_to_rgb(@dark_hsl));
}

# from https://github.com/darkreader/
sub darken {
    my ($h, $s, $l) = @_;

    my $l_max            = 0.9;
    my $l_min_s0         = 0.7;
    my $l_min_s1         = 0.6;
    my $s_neutral_lim_l0 = 0.12;
    my $s_neutral_lim_l1 = 0.36;
    my $s_coloured       = 0.24;
    my $h_coloured_l0    = 35;
    my $h_coloured_l1    = 45;

    my $l_min = scale($s, 0, 1, $l_min_s0, $l_min_s1);
    my $l_x = $l < 0.5 ? scale($l, 0, 0.5, $l_max, $l_min) : max($l, $l_min);
    my $h_x = $h;
    my $s_x = $s;

    my $s_netural_lim = scale(clamp($l_x, $l_min, $l_max), $l_min, $l_max, $s_neutral_lim_l0, $s_neutral_lim_l1);
    if ($s < $s_netural_lim) {
        $s_x = $s_coloured;
        $h_x = scale(clamp($l_x, $l_min, $l_max), $l_min, $l_max, $h_coloured_l0, $h_coloured_l1);
    }

    return ($h_x, $s_x, $l_x);
}

sub rgb_to_hsl {
    my ($colour) = @_;

    die unless $colour =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/;
    my ($r, $g, $b) = (hex($1) / 255, hex($2) / 255, hex($3) / 255);

    my $max = max($r, $g, $b);
    my $min = min($r, $g, $b);
    my $c   = $max - $min;
    my $l   = ($max + $min) / 2;

    return { h => 0, s => 0, l => $l } if $c == 0;

    my $h = ($max == $r ? ((($g - $b) / $c) % 6) : ($max == $g ? (($b - $r) / $c + 2) : (($r - $g) / $c + 4))) * 60;
    $h += 360 if $h < 0;

    my $s = $c / (1 - abs(2 * $l - 1));

    return ($h, $s, $l);
}

sub hsl_to_rgb {
    my ($h, $s, $l) = @_;
    my ($r, $g, $b);

    if ($s == 0) {
        $r = $b = $g = $l;

    } else {
        my $c = (1 - abs(2 * $l - 1)) * $s;
        my $x = $c * (1 - abs(($h / 60) % 2 - 1));
        my $m = $l - $c / 2;
        if ($h < 60) {
            ($r, $g, $b) = map { $_ + $m } ($c, $x, 0);
        } elsif ($h < 120) {
            ($r, $g, $b) = map { $_ + $m } ($x, $c, 0);
        } elsif ($h < 180) {
            ($r, $g, $b) = map { $_ + $m } (0, $c, $x);
        } elsif ($h < 240) {
            ($r, $g, $b) = map { $_ + $m } (0, $x, $c);
        } elsif ($h < 300) {
            ($r, $g, $b) = map { $_ + $m } ($x, 0, $c);
        } else {
            ($r, $g, $b) = map { $_ + $m } ($c, 0, $x);
        }
    }

    return sprintf('#%02x%02x%02x', map { round($_ * 255) } ($r, $g, $b));
}

sub scale {
    my ($x, $in_low, $in_high, $out_low, $out_high) = @_;
    return ($x - $in_low) * ($out_high - $out_low) / ($in_high - $in_low) + $out_low;
}

sub clamp {
    my ($x, $min, $max) = @_;
    return min($max, max($min, $x));
}

sub round {
    my ($x) = @_;
    return $x > 0 ? floor($x + 0.50000000000008) : ceil($x - 0.50000000000008);
}

{
    tie(my %cache => 'Memoize::ExpireLRU', CACHESIZE => 5_000);  ## no critic (Miscellanea::ProhibitTies)
    memoize('nick_colour', [HASH => \%cache, SCALAR_CACHE => 'FAULT']);
}

1;
