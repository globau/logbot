package LogBot::Config;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use File::Basename qw( basename );
use File::Path qw( make_path );
use LogBot::Util qw( file_time normalise_channel path_for squash_error timestamp );
use Try::Tiny qw( catch try );
use YAML::Tiny ();

our @EXPORT_OK = qw(
    find_config config_for
    load_config reload_config load_all_configs
    save_config config_filename
);
use parent 'Exporter';

sub find_config {
    my ($name) = @_;
    return unless $name;

    # config filename
    foreach my $guess ($name, "_$name") {
        foreach my $file ($guess, "$guess.yaml", "$RealBin/etc/$guess", "$RealBin/etc/$guess.yaml") {
            return $file if -e $file;
        }
    }
    die "failed to find config file: $name\n";
}

sub config_for {
    my ($configs, $network) = @_;
    foreach my $file (keys %{$configs}) {
        return $configs->{$file} if $configs->{$file}->{name} eq $network;
    }
    return undef;
}

sub load_config {
    my ($config_file, %params) = @_;
    return unless $config_file;

    say 'loading config: ' . $config_file if $ENV{DEBUG};
    my $config = YAML::Tiny->read($config_file)->[0];

    # normalise channel names
    my $channels = delete $config->{channels};
    foreach my $channel (keys %{$channels}) {
        $config->{channels}->{ normalise_channel($channel) } = $channels->{$channel};
    }

    # normalise blocked channels
    $config->{blocked} = [sort map { /^#/ ? normalise_channel($_) : $_ } @{ $config->{blocked} // [] }];

    # normalise bot names
    $config->{bots} = [sort map {lc} @{ $config->{bots} }];

    # derived values that don't need to be persisted
    $config->{_derived} = {
        file     => $config_file,
        root     => glob(q{'} . $config->{path} . q{'}),         # expand ~
        time     => file_time($config_file),
        web      => $params{web},
        readonly => $params{web},
        is_dev   => substr(basename($config_file), 0, 1) eq '_',
    };

    if ($params{web}) {

        # build sorted channel list, and list of hidden/disabled channels
        my (@visible, @hidden);
        foreach my $channel (sort keys %{ $config->{channels} }) {
            next if $channels->{$channel}->{no_logs};
            if ($channels->{$channel}->{disabled} && !$channels->{$channel}->{web_only}) {
                push @hidden, normalise_channel($channel);
                next;
            }
            if ($channels->{$channel}->{hidden}) {
                push @hidden, normalise_channel($channel);
                next;
            }
            push @visible, { name => $channel, archived => $config->{channels}->{$channel}->{archived} };
        }

        $config->{_derived}->{visible_channels} = \@visible;
        $config->{_derived}->{hidden_channels}  = \@hidden;
    }

    # default timings
    $config->{timing}->{initial_ping_delay}      ||= 3 * 60;
    $config->{timing}->{max_reconnect_interval}  ||= 3 * 60;
    $config->{timing}->{ping_interval}           ||= 60;
    $config->{timing}->{ping_timeout}            ||= 30;
    $config->{timing}->{ping_timeout_attempts}   ||= 5;
    $config->{timing}->{channel_reload_interval} ||= 60 * 60;
    $config->{timing}->{topic_reload_interval}   ||= 24 * 60 * 60;
    $config->{timing}->{invite_cooldown}         ||= 3 * 60;

    make_path($config->{_derived}->{root});
    make_path(path_for($config, 'queue'));

    return $config;
}

sub reload_config {
    my ($config) = @_;
    my $config_file = $config->{_derived}->{file};
    return file_time($config_file) == $config->{_derived}->{time}
        ? $config
        : load_config($config_file, web => $config->{_derived}->{web});
}

sub save_config {
    my ($config) = @_;

    die 'cannot save to readonly config' if $config->{_derived}->{readonly};

    my $derived = delete $config->{_derived};
    my $config_file = $derived->{file} // die;
    say timestamp(), " -- saving config to $config_file" unless $ENV{CRON};

    try {
        my $yaml = YAML::Tiny->new($config);
        $yaml->write($config_file);
    }
    catch {
        say timestamp(), " !! failed to write to $config_file: ", squash_error($_);
    };

    $config->{_derived} = $derived;
}

sub config_filename {
    my ($config) = @_;
    return $config->{_derived}->{file};
}

my ($all_configs_hash, $all_configs) = ('');

sub load_all_configs {
    my (%params) = @_;

    # load all conf files

    #<<<
    my @files =
        grep { basename($_) ne '_sample.yaml' }
        $params{all}
            ? glob($RealBin . '/etc/*.yaml')
            : grep { substr(basename($_), 0, 1) ne '_' } glob($RealBin . '/etc/*.yaml');
    #>>>

    my $hash = '';
    foreach my $file (@files) {
        $hash .= $file . '.' . file_time($file);
    }

    if ($all_configs_hash ne $hash) {
        foreach my $file (@files) {
            $all_configs->{$file} = load_config($file, %params);
        }
        $all_configs_hash = $hash;
    }

    $all_configs // die "failed to find any configs\n";
    return $all_configs;
}

1;
