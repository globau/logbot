package LogBot::Config;

use strict;
use warnings;

use base 'LogBot::Base';

use fields qw(
    bot
    web
    data_path
    tmpl_path
);

sub new {
    my ($class, %args) = @_;

    my $self = fields::new($class);
    foreach my $field (keys %args) {
        $self->{$field} = $args{$field};
    }
    return $self;
}

1;
