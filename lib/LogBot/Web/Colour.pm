package LogBot::Web::Colour;
use local::lib;
use v5.10;
use strict;
use warnings;

use Digest::xxHash qw( xxhash32 );
use Memoize qw( memoize );
use Memoize::ExpireLRU ();

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

    my $h = $hash % 360;
    my $l = $h >= 30 && $h <= 210 ? 30 : 50;
    my $s = 20 + $hash % 80;

    return 'hsl(' . $h . ',' . $s . '%,' . $l . '%)';
}

{
    tie(my %cache => 'Memoize::ExpireLRU', CACHESIZE => 5_000);  ## no critic (Miscellanea::ProhibitTies)
    memoize('nick_colour', [HASH => \%cache, SCALAR_CACHE => 'FAULT']);
}

1;
