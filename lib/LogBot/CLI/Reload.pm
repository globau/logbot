package LogBot::CLI::Reload;
use local::lib;
use v5.10;
use strict;
use warnings;

use LogBot::Util qw( file_for slurp );

sub manifest {
    return {
        command => 'reload',
        usage   => 'reload',
        help    => 'signal to bot to reload config',
    };
}

sub execute {
    my ($self, $configs) = @_;

    foreach my $config (@{$configs}) {
        my $file = file_for($config, 'pid', 'logbot-irc');
        if (-e $file) {
            chomp(my $pid = slurp($file));
            say 'sending HUP to ' . $pid;
            kill('HUP', $pid);
        } else {
            say '"', $config->{name}, '" bot is not running';
        }
    }
}

1;
