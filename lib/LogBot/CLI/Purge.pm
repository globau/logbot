package LogBot::CLI::Purge;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );

sub manifest {
    return {
        command => 'purge',
        usage   => 'purge',
        help    => 'delete orphaned data',
    };
}

sub execute {
    my ($self, $configs) = @_;

    $ENV{NO_META} = 1;
    $ENV{DEBUG}   = 1;
    foreach my $config (@{$configs}) {
        system($RealBin . '/logbot-nightly', $config->{_derived}->{file});
    }
}

1;
