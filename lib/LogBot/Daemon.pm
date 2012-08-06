package LogBot::Daemon;

use strict;
use warnings;

use Carp qw(confess);
use Cwd qw(abs_path);
use Daemon::Generic;
use File::Basename;
use LogBot;
use LogBot::ConfigFile;
use LogBot::Constants;
use LogBot::IRC;
use Pod::Usage;

my $_log_filename;
my $_debugging = 0;
my $_running = 0;

sub start {
    $SIG{__DIE__} = sub { confess(@_) };
    newdaemon(configfile => 'logbot.conf');
}

sub gd_preconfig {
    my ($self) = @_;

    if (!LogBot->initialised) {
        my $config_file = LogBot::ConfigFile->new($self->{configfile});
        LogBot->new($self->{configfile}, LOAD_DELAYED);
        return (
            pidfile => $config_file->{data_path} . ($_debugging ? '/logbot-debug.pid' : '/logbot.pid'),
        );
    } else {
        LogBot->reload()
            || print LogBot->config_error . "\n";
    }
}

sub gd_postconfig {
    my ($self) = @_;

    if ($_log_filename) {
        close(STDERR);
        open(STDERR, ">>$_log_filename") or (print "could not open stderr: $!" && exit(1));
    }
}

sub gd_getopt {
    my ($self) = @_;

    if (grep { $_ eq '-d' } @ARGV) {
        @ARGV = qw(-c debug.conf -f start);
        $_debugging = 1;
    }

    $self->SUPER::gd_getopt();
}

sub gd_usage {
    pod2usage({ -verbose => 0, -exitval => 'NOEXIT' });
    return 0;
};

sub gd_redirect_output {
    my ($self) = @_;
    $_log_filename = LogBot->config->{data_path} . '/logbot.log';
    open(STDERR, ">>$_log_filename") or (print "could not open stderr: $!" && exit(1));
    close(STDOUT);
    open(STDOUT, ">&STDERR") or die "redirect STDOUT -> STDERR: $!";
}

sub gd_setup_signals {
    my ($self) = @_;
    $self->SUPER::gd_setup_signals();
    $SIG{TERM} = sub { $self->gd_quit_event(); }
}

sub gd_run {
    my ($self) = @_;
    $_running = 1;
    LogBot::IRC->start();
}

1;
