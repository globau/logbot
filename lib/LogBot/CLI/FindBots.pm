package LogBot::CLI::FindBots;
use local::lib;
use v5.10;
use strict;
use warnings;

use List::Util qw( any );
use LogBot::Database qw( dbh );

sub manifest {
    return {
        command => 'find-bots',
        usage   => 'find-bots',
        help    => 'find nicks ending in "bot"',
    };
}

sub execute {
    my ($self, $configs) = @_;

    my $since = DateTime->now->subtract(months => 6)->epoch;

    foreach my $config (@{$configs}) {
        say $config->{name};

        my $dbh = dbh($config);
        my @nicks =
            sort
            map {lc}
            @{ $dbh->selectcol_arrayref("SELECT DISTINCT(nick) FROM logs WHERE time >= $since AND nick LIKE '%bot'") };

        say '> no bots' unless @nicks;

        foreach my $nick (@nicks) {
            if (any { $_ eq $nick } @{ $config->{bots} }) {
                say "✓ $nick";
            } else {
                say "- $nick";
            }
        }
    }
}

1;
