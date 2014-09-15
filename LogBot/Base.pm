package LogBot::Base;
use LogBot::BP;

# updates $self from an $args hashref; $imutable is an arrayref of args which can't be changed.
# returns a list of fields which were changed.
sub update_from_args {
    my ($self, $imutable, $args) = @_;

    my @changed;
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

        if (!$unchanged) {
            $self->{$field} = $args->{$field};
            push @changed, $field;
        }
    }
    return @changed;
}

1;
