package LogBot::ConfigFile;
use LogBot::BP;

use fields qw(
    bot
    web
    data_path
    tmpl_path
    networks
    filename
    _context
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
use constant LIST  => 3;

use constant MAND  => 1;
use constant OPT   => 0;

use constant TRUE  => 1;
use constant FALSE => 0;

#
# initialisation
#

sub new {
    my ($class, $filename) = @_;
    my $self = fields::new($class);
    $self->{filename} = $filename;
    $self->load();
    return $self;
}

sub load {
    my ($self) = @_;

    $/ = "\n";
    my %config = Config::General->new(
        -ConfigFile => $self->{filename},
        -AllowMultiOptions => 'no',
        -AutoTrue => 'yes',
        -LowerCaseNames => 'yes',
    )->getall();
    my $config = \%config;

    $self->{networks} = {};
    $self->{_missing} = [];
    $self->{_invalid} = [];

    $self->{data_path} = $self->_value($config, 'data_path', STR, MAND);
    $self->{data_path} =~ s/\/$//;

    $self->{bot}->{debug_irc} = $self->_value($config->{bot}, 'debug_irc', BOOL, OPT, FALSE);

    $self->{web}->{default_network} = $self->_value($config->{web}, 'default_network', STR, MAND);
    $self->{web}->{default_channel} = canon_channel($self->_value($config->{web}, 'default_channel', STR, MAND));
    $self->{web}->{search_limit}    = $self->_value($config->{web}, 'search_limit', INT, OPT, 1000);

    foreach my $network_name (keys %{$config->{network}}) {
        my $network_config = $config->{network}->{$network_name};
        my $network = {};
        $self->{_context} = $network_name;

        $network->{network} = $network_name;
        $network->{server} = $self->_value($network_config, 'server', STR, MAND);
        $network->{port} = $self->_value($network_config, 'port', INT, OPT, 6667);

        $network->{nick} = $self->_value($network_config, 'nick', STR, MAND);
        $network->{name} = $self->_value($network_config, 'name', STR, MAND);
        $network->{password} = $self->_value($network_config, 'password', STR, OPT, '');

        my $bots = $self->_value($network_config, 'bots', STR, OPT, '');
        my @bots = map { lc_irc($_) } split(/\s+/, $bots);
        $network->{bots} = \@bots;

        $network->{channels} = {};
        if (exists $network_config->{channel}) {
            foreach my $key (keys %{$network_config->{channel}}) {
                my $channel_config = $network_config->{channel}{$key};
                my $channel_name = canon_channel($key);
                my $channel = {};
                $self->{_context} = sprintf("%s : %s", $network_name, $channel_name);

                $channel->{name} = $channel_name;
                $channel->{password} = $self->_value($channel_config, 'password', STR, OPT, '');
                $channel->{visibility} = $self->_value($channel_config, 'visibility', LIST, OPT, 'public', 'public|hidden|private');
                $channel->{in_channel_search} = $self->_value($channel_config, 'in_channel_search', BOOL, OPT, TRUE);
                $channel->{log_events} = $self->_value($channel_config, 'log_events', BOOL, OPT, TRUE);
                $channel->{join} = $self->_value($channel_config, 'join', BOOL, OPT, TRUE);

                $network->{channels}->{$channel_name} = $channel;
            }
        }

        $self->{networks}->{$network_name} = $network;
    }

    if (@{$self->{_missing}} || @{$self->{_invalid}}) {
        my $error = "Failed to load " . $self->{filename} . ":\n";
        $error .= $self->_report_error($self->{_missing}, 'missing');
        $error .= $self->_report_error($self->{_invalid}, 'invalid');
        die "$error\n";
    }
}

sub _value {
    my ($self, $config, $name, $type, $mandatory, $default, $list_values) = @_;

    if (!$mandatory && !defined($default)) {
        die "must provide default value for optional '$name'";
    }

    if ($mandatory && !exists $config->{$name}) {
        push @{$self->{_missing}}, $self->{_context} . " : $name";
        return;
    }

    my $value = $config->{$name};
    $value = $default unless defined $value;

    my $valid = 1;
    if ($type == STR) {
        $value =~ s/(^\s+|\s+$)//g;
    } elsif ($type == INT) {
        $valid = 0 if $value =~ /\D/;
    } elsif ($type == BOOL) {
        $value = $value ? 1 : 0;
    } elsif ($type == LIST) {
        my @valid = split(/\|/, lc($list_values));
        $valid = (grep { lc($_) eq $value } @valid) ? 1 : 0;
        $value = lc($value) if $valid;
    }
    if (!$valid) {
        push @{$self->{_invalid}}, $self->{_context} . " : $name ($value)";
        return;
    }

    return $value;
}

sub _report_error {
    my ($self, $fields, $description) = @_;
    return '' unless @$fields;
    my @result;
    if (scalar @$fields == 1) {
        push @result, "the following option is $description:";
    } else {
        push @result, "the following options are $description:";
    }
    foreach my $field (@$fields) {
        push @result, "  $field";
    }
    return join("\n", @result);
}

1;
