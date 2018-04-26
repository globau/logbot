package LogBot::Web::Index;
use local::lib;
use v5.10;
use strict;
use warnings;

sub render {
    my ($c, $params) = @_;

    if (my $error = $params->{error}) {
        $c->stash(
            channel => '',
            error   => $error,
        );
    }

    $c->stash(page => 'index');
    return $c->render('index');
}

1;
