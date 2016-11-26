package LogBot::Network;
use LogBot::BP;

use base 'LogBot::Base';

use fields qw(
    network
    name
    nick password
    server port
    bots
    bot
    _channels
);

use constant IMUTABLE_FIELDS => qw(
    network
    name
);

use IRC::Utils ':ALL';
use LogBot::Constants;
use LogBot::Util;

sub new {
    my ($class, %args) = @_;
    my $self = fields::new($class);
    foreach my $field (keys %args) {
        next if $field =~ /^_/;
        $self->{$field} = $args{$field};
    }
    $self->{_channels} = {};
    LogBot->action(ACTION_NETWORK_CONNECT, $self);
    return $self;
}

sub reconfigure {
    my ($self, %args) = @_;

    my @changed = $self->update_from_args([ IMUTABLE_FIELDS ], \%args);

    if (grep { $_ eq 'server' || $_ eq 'port' } @changed) {
        LogBot->action(ACTION_NETWORK_RECONNECT, $self);

    } elsif (grep { $_ eq 'nick' } @changed) {
        LogBot->action(ACTION_NETWORK_NICK, $self);
    }
}

sub connect {
    my ($self) = @_;

    if (!$self->{bot}) {
        LogBot::IRC->connect_network($self);
    }
}

sub add_channel {
    my ($self, $channel) = @_;

    if ($self->channel($channel->{name})) {
        die "internal error: network->add_channel called instead of channel->reconfigure";
    }
    $self->{_channels}->{$channel->{name}} = $channel;

    LogBot->action(ACTION_CHANNEL_JOIN, $self, $channel);
}

sub remove_channel {
    my ($self, $channel) = @_;

    $channel = $self->channel($channel->{name});
    return unless $channel;
    delete $self->{_channels}{$channel};

    LogBot->action(ACTION_CHANNEL_PART, $self, $channel);
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

1;
