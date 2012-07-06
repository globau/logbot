package LogBot::Command::Ping;

use strict;
use warnings;

use LogBot::Util;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->{bot} = shift;
    return $self;
}

sub execute {
    my ($self, $network, $channel, $nick, $command) = @_;
    return unless lc($command) eq 'ping';

    $self->{bot}->respond($channel, $nick, 'pong');
    return 1;
}

1;
