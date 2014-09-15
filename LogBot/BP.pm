package LogBot::BP;

# common/boilerplater code

use strict;
use warnings;

use Carp qw(confess);
use Data::Dumper;

BEGIN {
    # because we log times as UTC, force all our timezone dates to UTC
    $ENV{TZ} = 'UTC';
    # always die with a stack trace
    $SIG{__DIE__} = sub {
        confess(@_);
    };
    # always sort keys when debugging
    $Data::Dumper::Sortkeys = 1;
}

sub import {
    # utf8
    binmode(STDOUT, ":utf8");
    binmode(STDERR, ":utf8");

    # enable strict, warnings
    strict->import();
    warnings->import();

    # auto-use app-wide packages
    my $dest_pkg = caller();
    eval "
        package $dest_pkg;
        use LogBot;
        use LogBot::Constants;
        use LogBot::Util;
    ";
    die $@ if $@;
}

1;
