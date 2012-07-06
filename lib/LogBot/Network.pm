package LogBot::Network;

use strict;
use warnings;

use fields qw(
    network
    name
    nick real_name password
    server port
    bots
    _channels
);

use IRC::Utils ':ALL';
use LogBot::Config;
use LogBot::Util;

sub new {
    my $class = shift;
    my $self = fields::new($class);
    $self->{network} = shift;
    return $self;
}

sub channel {
    my ($self, $channel) = @_;
    $channel = canon_channel($channel);
    if (!exists $self->{_channels}{$channel}) {
        return;
    }
    return $self->{_channels}{$channel};
}

sub channels {
    my ($self) = @_;
    return sort { $a->{name} cmp $b->{name} } values %{$self->{_channels}};
}

sub public_channels {
    my ($self) = @_;
    return grep { $_->{public} } $self->channels;
}

sub config {
    my ($self) = @_;
    my $config = LogBot::Config->instance;
    foreach my $network_config ($config->networks) {
        next unless $network_config->{network} eq $self->{network};
        return $network_config;
    }
    return;
}

1;
