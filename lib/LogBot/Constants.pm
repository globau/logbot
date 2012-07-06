package LogBot::Constants;

use strict;
use warnings;

use base 'Exporter';

our @EXPORT = qw(
    EVENT_PUBLIC
    EVENT_JOIN
    EVENT_PART
    EVENT_ACTION
    EVENT_QUIT

    MAX_BROWSE_DAY_SPAN
);

use constant EVENT_PUBLIC   => 0;
use constant EVENT_JOIN     => 1;
use constant EVENT_PART     => 2;
use constant EVENT_ACTION   => 3;
use constant EVENT_QUIT     => 4;

use constant MAX_BROWSE_DAY_SPAN => 28;

1;
