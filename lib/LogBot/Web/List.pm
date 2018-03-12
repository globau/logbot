package LogBot::Web::List;
use local::lib;
use v5.10;
use strict;
use warnings;

sub render {
    my ($c, $params) = @_;
    return $c->render('list');
}

1;
