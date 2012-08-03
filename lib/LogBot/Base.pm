package LogBot::Base;

use strict;
use warnings;

sub update_from_args {
    my ($self, $imutable, $args) = @_;

    foreach my $field (keys %$args) {
        my $unchanged = 0;
        if ($field =~ /^_/) {
            $unchanged = 1;

        } elsif (grep { $_ eq $field } @$imutable) {
            $unchanged = 1;

        } elsif (ref($args->{$field}) eq 'ARRAY') {
            if (scalar(@{ $self->{$field} }) == scalar(@{ $args->{$field} })) {
                $unchanged = 1;
                foreach my $e (@{ $args->{$field} }) {
                    if (!grep { $_ eq $e } @{ $self->{$field} }) {
                        $unchanged = 0;
                        last;
                    }
                }
                foreach my $e (@{ $self->{$field} }) {
                    if (!grep { $_ eq $e } @{ $args->{$field} }) {
                        $unchanged = 0;
                        last;
                    }
                }
            }

        } elsif (ref($args->{$field})) {
            die "$field unsupported";

        } elsif ($self->{$field} eq $args->{$field}) {
            $unchanged = 1;
        }

        if ($unchanged) {
            delete $args->{$field};
        } else {
            $self->{$field} = $args->{$field};
        }
    }
}

1;
