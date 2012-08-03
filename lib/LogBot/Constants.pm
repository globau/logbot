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

    ACTION_NETWORK_CONNECT
    ACTION_NETWORK_RECONNECT
    ACTION_NETWORK_NICK
    ACTION_NETWORK_DISCONNECT
    ACTION_CHANNEL_JOIN
    ACTION_CHANNEL_PART

    MAX_BROWSE_DAY_SPAN
);

use constant EVENT_PUBLIC   => 0;
use constant EVENT_JOIN     => 1;
use constant EVENT_PART     => 2;
use constant EVENT_ACTION   => 3;
use constant EVENT_QUIT     => 4;

use constant ACTION_NETWORK_CONNECT    => 0;
use constant ACTION_NETWORK_RECONNECT  => 1;
use constant ACTION_NETWORK_NICK       => 2;
use constant ACTION_NETWORK_DISCONNECT => 3;
use constant ACTION_CHANNEL_JOIN       => 4;
use constant ACTION_CHANNEL_PART       => 5;

use constant MAX_BROWSE_DAY_SPAN => 28;

1;
