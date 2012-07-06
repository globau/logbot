package LogBot::Util;

use strict;
use warnings;

use base 'Exporter';

our @EXPORT = qw(
    canon_channel
    sanatise_perl_error
    required
    merge_in
    pretty_size
    commify
    now
    trim
);

use DateTime;
use Time::HiRes;
use Time::Local;

sub canon_channel {
    my $channel = lc shift;
    return '' if $channel eq '';
    $channel =~ s/(^\s+|\s+$)//g;
    $channel = '#'.$channel unless $channel =~ /^#/;
    return $channel;
}

sub sanatise_perl_error {
    my $error = shift;
    # blah at lib/LogBot/Command/Seen.pm line 24.
    $error = $1 if $error =~ /^([^\n]+)/;
    $error =~ s/ at \S+ line \d+\.$//;
    return $error;
}

sub required {
    my ($rh, @keys) = @_;
    foreach my $key (@keys) {
        # XXX use cinfess/croak
        if (!exists $rh->{$key}) {
            die "A value is required for '$key'\n";
        }
    }
}

sub merge_in {
    my ($rh_dest, $rh_source, $rh_defaults) = @_;
    foreach my $key (keys %$rh_defaults) {
        if (!defined($rh_dest->{$key})) {
            $rh_dest->{$key} = exists($rh_source->{$key}) ? $rh_source->{$key} : $rh_defaults->{$key};
        }
    }
}

sub pretty_size {
    my $bytes = shift;
    my @base = ('b', 'k', 'm', 'g', 't');
    my $base = 0;
    while($bytes / 1024 >= 1) {
        $base++;
        $bytes = $bytes / 1024;
    }
    $base && ($bytes = sprintf "%.1f", $bytes);
    return $bytes . $base[$base];
}

sub commify {
    my $n = shift;
    1 while $n =~ s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $n;
}

sub now {
    # because DateTime->now() doesn't use hires time
    return DateTime->from_epoch(epoch => Time::HiRes::time());
}

sub trim {
    my $v = shift;
    $v =~ s/(^\s+|\s+$)//g;
    return $v;
}

1;
