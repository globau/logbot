package LogBot::Web::Config;
use local::lib;
use v5.10;
use strict;
use warnings;

sub render {
    my ($c, $params) = @_;
    $c->stash(page => 'config');
    return $c->render('config');
}

1;
