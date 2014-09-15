package LogBot::Daemon;
use LogBot::BP;

use Daemon::Generic;
use DateTime;
use FindBin qw($RealBin);
use File::Basename;
use IO::Handle;
use LogBot::IRC;
use Pod::Usage;

my $_debugging = 0;
my $_running = 0;

sub start {
    newdaemon(configfile => "$RealBin/logbot.conf");
}

sub gd_preconfig {
    my ($self) = @_;

    if (!LogBot->initialised) {
        LogBot->init($self->{configfile}, LOAD_DELAYED);
        return (
            pidfile => LogBot->config_file->{data_path} . ($_debugging ? '/logbot-debug.pid' : '/logbot.pid'),
        );
    } else {
        LogBot->reload()
            || print LogBot->config_error . "\n";
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
    tie(*STDERR => 'LogBot::Daemon::stderr', \&_log);
}

sub gd_reopen_output {
    # no-op
}

my $_log_filename = '';
my $_log_filehandle;
sub _log {
    my ($line) = @_;
    chomp($line);

    if ($_debugging) {
        print $line, "\n";
    }

    my $now = DateTime->now();
    my $filename = LogBot->config
        ? LogBot->config->{data_path} . '/log/logbot-'
        : "$RealBin/data/log/logbot-";
    $filename .= $now->ymd('') . '.log';
    if ($_log_filename ne $filename) {
        $_log_filename = $filename;
        unless (open($_log_filehandle, ">>$_log_filename")) {
            print "could not create $_log_filename $!\n";
            exit(1);
        }
        $_log_filehandle->autoflush();
    }
    print $_log_filehandle '[' . $now->hms(':') . ']' . $line . "\n";
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

package LogBot::Daemon::stderr;

use strict;

sub TIEHANDLE {
    my ($class) = @_;
    bless({ callback => $_[1] }, $class);
}

sub PRINT {
    my $self = shift;
    $self->{callback}->(join('', @_));
}

sub PRINTF {
    &PRINT($_[0], sprintf($_[1], @_[2..$#_]));
}

sub OPEN {}
sub READ {}
sub READLINE {}
sub GETC {}
sub WRITE {}
sub FILENO {}
sub CLOSE {}
sub DESTROY {}

1;
