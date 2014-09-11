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
    shorten
    simple_date_string
);

use DateTime;
use Time::HiRes;
use Time::Local;

sub canon_channel {
    # ensures a channel name always has the same format
    # lowercase, trimmed, and with a # prefix
    my $channel = lc shift;
    return '' if $channel eq '';
    $channel =~ s/(^\s+|\s+$)//g;
    $channel = '#'.$channel unless $channel =~ /^#/;
    return $channel;
}

sub sanatise_perl_error {
    # truncates an error to just the error message itself
    # blah at lib/LogBot/Command/Seen.pm line 24.
    my $error = shift;
    $error = $1 if $error =~ /^([^\n]+)/;
    $error =~ s/ at \S+ line \d+\.$//;
    return $error;
}

sub required {
    # dies unless all keys are present in the hash
    my ($rh, @keys) = @_;
    foreach my $key (@keys) {
        # TODO use confess/croak
        if (!exists $rh->{$key}) {
            die "A value is required for '$key'\n";
        }
    }
}

sub merge_in {
    # merges source into dest, using keys from defaults
    my ($rh_dest, $rh_source, $rh_defaults) = @_;
    foreach my $key (keys %$rh_defaults) {
        if (!defined($rh_dest->{$key})) {
            $rh_dest->{$key} = exists($rh_source->{$key}) ? $rh_source->{$key} : $rh_defaults->{$key};
        }
    }
}

sub pretty_size {
    # make bytes readable
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
    # commas, in numbers
    my $n = shift;
    1 while $n =~ s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $n;
}

sub now {
    # because DateTime->now() doesn't use hires time
    return DateTime->from_epoch(epoch => Time::HiRes::time());
}

sub trim {
    # why isn't this a core perl function?
    my $v = shift;
    $v =~ s/(^\s+|\s+$)//g;
    return $v;
}

sub shorten {
    # trims the middle of a string
    my ($value) = @_;
    return $value if length($value) < 70;
    while (length($value) >= 70) {
        substr($value, length($value) / 2 - 1, 3) = '';
    }
    substr($value, length($value) / 2, 3) = '...';
    return $value;
}

sub simple_date_string {
    # returns a date with time (if within the last week)
    # or a date with the year otherwise
    my ($date) = @_;
    if ($date->delta_days(now())->in_units('days') > 7) {
        return $date->strftime('%b %e %Y');
    } else {
        return $date->strftime('%b %e %H:%M');
    }
}

1;
