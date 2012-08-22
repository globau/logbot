package LogBot;

use strict;
use warnings;
use feature qw(switch);

use LogBot::Config;
use LogBot::ConfigFile;
use LogBot::Constants;
use LogBot::Network;

use fields qw(
    _config_filename
    _config
    _networks
    _is_daemon
    _actions
    _config_error
);

#
# initialisation
#

# this class is a singleton
my $self;

sub initialised {
    return $self ? 1 : 0;
}

sub new {
    my ($class, $config_filename, $load) = @_;

    $self ||= fields::new($class);

    $self->{_config_filename} = $config_filename;
    $self->{_is_daemon} = 0;
    $self->{_actions} = [];

    if ($load == LOAD_IMMEDIATE) {
        unless ($self->reload()) {
            die $self->config_error . "\n";
        }
    };

    return $self;
}

sub instance {
    return $self;
}

sub reload {
    my ($class) = @_;

    my $config_file;
    eval {
        $config_file = LogBot::ConfigFile->new($self->{_config_filename});
    };
    if ($@) {
        my @error;
        foreach my $line (split /\n/, $@) {
            last if $line =~ /^\s* at \//;
            push @error, $line;
        }
        $self->{_config_error} = join("\n", @error);
        return;
    }

    $self->{_config} = LogBot::Config->new(
        bot => $config_file->{bot},
        web => $config_file->{web},
        data_path => $config_file->{data_path},
        tmpl_path => $config_file->{tmpl_path},
    );

    foreach my $network_name (sort keys %{ $config_file->{networks} }) {
        my $config_network = $config_file->{networks}->{$network_name};
        my %args = (
            network  => $network_name,
            server   => $config_network->{server},
            port     => $config_network->{port},
            nick     => $config_network->{nick},
            name     => $config_network->{name},
            password => $config_network->{password},
            bots     => $config_network->{bots},
        );
        my $network = $self->network($network_name);
        if (!$network) {
            $network = LogBot::Network->new(%args);
            $self->{_networks}->{$network_name} = $network;
        } else {
            $network->reconfigure(%args);
        }

        # XXX delete network

        foreach my $channel_name (sort keys %{ $config_network->{channels} }) {
            my $config_channel = $config_network->{channels}->{$channel_name};
            %args = (
                network           => $network,
                name              => $channel_name,
                password          => $config_channel->{password},
                public            => $config_channel->{visibility} eq 'public',
                hidden            => $config_channel->{visibility} eq 'hidden',
                in_channel_search => $config_channel->{in_channel_search},
                log_events        => $config_channel->{log_events},
                join              => $config_channel->{join},
            );
            my $channel = $network->channel($channel_name);
            if (!$channel) {
                $channel = LogBot::Channel->new(%args);
                $network->add_channel($channel);
            } else {
                $channel->reconfigure(%args);
            }
        }

        foreach my $channel ($network->channels) {
            next if exists $config_network->{channels}->{$channel->{name}};
            $network->remove_channel($channel);
        }

        if ($self->is_daemon) {
            $self->do_actions();
        }
    }

    return 1;
}

sub connect {
    $self->{_is_daemon} = 1;
    $self->reload();
}

sub is_daemon {
    return $self->{_is_daemon};
}

sub config {
    return $self->{_config};
}

sub config_error {
    return $self->{_config_error};
}

sub networks {
    return
        sort { $a->{network} cmp $b->{network} }
        values %{ $self->{_networks} };
}

sub network {
    my ($class, $name) = @_;
    if (!exists $self->{_networks}->{$name}) {
        return;
    }
    return $self->{_networks}->{$name};
}

# when an object (such as Network or Channel) is told to (re)configure, it
# pushes an action to this class.  then, once all reconfiguration has taken
# place, if we're running as a deamon we take the required action.

sub action {
    my ($class, $type, $network, $channel) = @_;
    return unless $self->is_daemon;
    push @{ $self->{_actions} }, {
        type    => $type,
        network => $network,
        channel => $channel,
    };
}

sub do_actions {
    while (my $action = shift @{ $self->{_actions} }) {
        my ($network, $channel) = ($action->{network}, $action->{channel});
        given($action->{type}) {
            when(ACTION_NETWORK_CONNECT) {
                $self->_remove_actions(network => $network);
                $network->connect();
            }
            when(ACTION_NETWORK_RECONNECT) {
                $self->_remove_actions(network => $network);
                $network->disconnect();
                $network->connect();
            }
            when(ACTION_NETWORK_NICK) {
                die "not implemented";
            }
            when(ACTION_NETWORK_DISCONNECT) {
                $self->_remove_actions(network => $network);
                $network->disconnect();
            }
            when(ACTION_CHANNEL_JOIN) {
                $self->_remove_actions(channel => $channel);
                $network->{bot}->join($channel);
            }
            when(ACTION_CHANNEL_PART) {
                $self->_remove_actions(channel => $channel);
                $network->{bot}->part($channel);
            }
        }
    }
}

sub _remove_actions {
    my ($class, %args) = @_;

    foreach my $name (keys %args) {
        my $object = $args{$name};
        $self->{_actions} = [
            grep { $_->{$name} eq $object}
            @{ $self->{_actions} }
        ];
    }
}

1;
