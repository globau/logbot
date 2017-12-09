package LogBot::Config;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use File::Basename qw( basename dirname );
use File::Path qw( make_path );
use LogBot::Util qw( normalise_channel path_for squash_error timestamp );
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
    foreach my $file (keys %$configs) {
        return $configs->{$file} if $configs->{$file}->{name} eq $network;
    }
    return;
}

sub load_config {
    my ($config_file, %params) = @_;
    return unless $config_file;

    say 'loading config: ' . $config_file if $ENV{DEBUG};
    my $config = YAML::Tiny->read($config_file)->[0];

    # normalise channel keys
    my $channels = delete $config->{channels};
    foreach my $channel (keys %$channels) {
        if ($params{web}) {
            next if $channels->{$channel}->{no_logs};
            next if $channels->{$channel}->{disabled} && !$channels->{$channel}->{web_only};
        }
        $config->{channels}->{ normalise_channel($channel) } = $channels->{$channel};
    }

    # normalise blocked channels
    $config->{blocked} = [sort map { normalise_channel($_) } @{ $config->{blocked} // [] }];

    # normalise bot names
    $config->{bots} = [sort map { lc($_) } @{ $config->{bots} }];

    # internal values that don't need to be persisted
    $config->{_internal} = {
        file     => $config_file,
        root     => glob("'" . $config->{path} . "'"),  # expand ~
        time     => (stat($config_file))[9],
        web      => $params{web},
        readonly => $params{web},
    };

    make_path($config->{_internal}->{root});
    make_path(path_for($config, 'queue'));

    return $config;
}

sub reload_config {
    my ($config) = @_;
    my $config_file = $config->{_internal}->{file};
    return (stat($config_file))[9] == $config->{_internal}->{time}
        ? $config
        : load_config($config_file, web => $config->{_internal}->{web});
}

sub save_config {
    my ($config) = @_;

    die "cannot save to readonly config" if $config->{_internal}->{readonly};

    my $internal = delete $config->{_internal};
    my $config_file = $internal->{file} // die;
    say timestamp(), " -- saving config to $config_file" unless $ENV{CRON};

    try {
        my $yaml = YAML::Tiny->new($config);
        $yaml->write($config_file);
    }
    catch {
        say timestamp(), " !! failed to write to $config_file: ", squash_error($_);
    };

    $config->{_internal} = $internal;
}

sub config_filename {
    my ($config) = @_;
    return $config->{_internal}->{file};
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
        $hash .= $file . '.' . ((stat($file))[9]);
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
