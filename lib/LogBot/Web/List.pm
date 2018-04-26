package LogBot::Web::List;
use local::lib;
use v5.10;
use strict;
use warnings;

sub render {
    my ($c, $params) = @_;
    $c->stash(page => 'list');
    return $c->render('list');
}

1;
