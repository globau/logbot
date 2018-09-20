package LogBot::CLI::LogRotate;
use local::lib;
use v5.10;
use strict;
use warnings;

use LogBot::Util qw( file_for slurp );

sub manifest {
    return {
        command => 'log-rotate',
        usage   => 'log-rotate',
        help    => 'rotate log files (all irc and web daemons)',
    };
}

sub execute {
    my ($self, $configs) = @_;

    foreach my $config (@{$configs}) {
        my $file = file_for($config, 'pid', 'logbot-irc');
        next unless -e $file;
        chomp(my $pid = slurp($file));
        kill('USR2', $pid);
    }
}

1;
