package LogBot::ConfigFile;

use strict;
use warnings;
use feature qw(switch);

use fields qw(
    bot
    web
    data_path
    tmpl_path
    _networks
    _conf_filename
    _missing _invalid
);

use Config::General;
use LogBot::Channel;
use LogBot::Constants;
use LogBot::Network;
use LogBot::Util;
use IRC::Utils ':ALL';

use constant STR   => 0;
use constant INT   => 1;
use constant BOOL  => 2;

use constant MAND  => 1;
use constant OPT   => 0;

use constant TRUE  => 1;
use constant FALSE => 0;

#
# initialisation
#

my $_instance;

sub init {
    die "double init" if $_instance;
    my ($class, $conf_filename) = @_;
    $_instance = fields::new($class);
    $_instance->{_conf_filename} = $conf_filename;
    $_instance->reload();
}

sub instance {
    die "not inited" unless $_instance;
    return $_instance;
}

sub reload {
    my ($self) = @_;

    $/ = "\n";
    my %config = Config::General->new(
        -ConfigFile => $self->{_conf_filename},
        -AllowMultiOptions => 'no',
        -AutoTrue => 'yes',
        -LowerCaseNames => 'yes',
    )->getall();

    $self->_load(\%config);
}

sub networks {
    my ($self) = @_;
    return sort { $a->{network} cmp $b->{network} } @{$self->{_networks}};
}

sub network {
    my ($self, $name) = @_;
    my @networks = grep { $_->{network} eq $name } $self->networks;
    return @networks ? $networks[0] : undef;
}

sub _load {
    my ($self, $config, $schema) = @_;

    $self->{_networks} = [];
    $self->{_missing} = [];
    $self->{_invalid} = [];

    $self->{data_path} = $self->_value($config, 'data_path', STR, MAND);
    $self->{data_path} =~ s/\/$//;

    $self->{bot}->{debug_poe} = $self->_value($config->{bot}, 'debug_poe', BOOL, OPT, FALSE);
    $self->{bot}->{debug_irc} = $self->_value($config->{bot}, 'debug_irc', BOOL, OPT, FALSE);

    $self->{web}->{default_network} = $self->_value($config->{web}, 'default_network', STR, MAND);
    $self->{web}->{default_channel} = canon_channel($self->_value($config->{web}, 'default_channel', STR, MAND));
    $self->{web}->{search_limit}    = $self->_value($config->{web}, 'search_limit', INT, OPT, 1000);

    foreach my $network_name (keys %{$config->{network}}) {
        my $network_config = $config->{network}->{$network_name};
        my $network = LogBot::Network->new($network_name);

        $network->{server} = $self->_value($network_config, 'server', STR, MAND);
        $network->{port} = $self->_value($network_config, 'port', INT, OPT, 6667);

        $network->{nick} = $self->_value($network_config, 'nick', STR, MAND);
        $network->{name} = $self->_value($network_config, 'name', STR, MAND);
        $network->{password} = $self->_value($network_config, 'password', STR, OPT, '');

        my $bots = $self->_value($network_config, 'bots', STR, OPT, '');
        my @bots = map { lc_irc($_) } split(/\s+/, $bots);
        $network->{bots} = \@bots;

        $network->{_channels} = {};
        if (exists $network_config->{channel}) {
            foreach my $key (keys %{$network_config->{channel}}) {
                my $channel_config = $network_config->{channel}{$key};
                my $channel_name = canon_channel($key);
                my $channel = LogBot::Channel->new($network_name, $channel_name);

                $channel->{public} = $self->_value($channel_config, 'public', BOOL, OPT, FALSE);
                $channel->{in_channel_search} = $self->_value($channel_config, 'in_channel_search', BOOL, OPT, TRUE);
                $channel->{log_events} = $self->_value($channel_config, 'log_events', BOOL, OPT, TRUE);
                $channel->{join} = $self->_value($channel_config, 'join', BOOL, OPT, TRUE);

                $network->{_channels}->{$channel_name} = $channel;
            }
        }

        push @{$self->{_networks}}, $network;
    }

    if (@{$self->{_missing}} || @{$self->{_invalid}}) {
        $self->_report_error($self->{_missing}, 'missing');
        $self->_report_error($self->{_invalid}, 'invalid');
        exit;
    }
}

sub _value {
    my ($self, $config, $name, $type, $mandatory, $default) = @_;

    if (!$mandatory && !defined($default)) {
        die "must provide default value for optional '$name'";
    }

    if ($mandatory && !exists $config->{$name}) {
        push @{$self->{_missing}}, $name;
        return;
    }

    my $value = $config->{$name};
    $value = $default unless defined $value;

    my $valid = 1;
    given($type) {
        when(STR)  { $value =~ s/(^\s+|\s+$)//g }
        when(INT)  { $valid = 0 if $value =~ /\D/ }
        when(BOOL) { $value = $value ? 1 : 0 }
    }
    if (!$valid) {
        push @{$self->{_invalid}}, $name;
        return;
    }

    return $value;
}

sub _report_error {
    my ($self, $fields, $description) = @_;
    return unless @$fields;
    if (scalar @$fields == 1) {
        print "the following option in " . $self->{_conf_filename} . " is $description:\n";
    } else {
        print "the following options in " . $self->{_conf_filename} . " are $description:\n";
    }
    foreach my $field (@$fields) {
        print "  $field\n";
    }
}

1;
