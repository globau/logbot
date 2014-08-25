package LogBot::Bot;

use strict;
use warnings;

use Carp;
use IRC::Utils ':ALL';
use LogBot::Command::Ping;
use LogBot::Command::Bug;
use LogBot::Command::Search;
use LogBot::Command::Seen;
use LogBot::Constants;
use LogBot::Event;
use LogBot::Util;

use fields qw(
    _irc
    _network
    _commands
);

#
# initialisation
#

sub new {
    my LogBot::Bot $self = shift;
    $self = fields::new($self) unless ref $self;

    $self->{_irc} = shift;
    $self->{_network} = shift;

    push @{$self->{_commands}}, LogBot::Command::Bug->new($self);
    push @{$self->{_commands}}, LogBot::Command::Ping->new($self);
    push @{$self->{_commands}}, LogBot::Command::Seen->new($self);
    # search must be last in the list
    push @{$self->{_commands}}, LogBot::Command::Search->new($self);

    return $self;
}

#
# methods
#

sub join {
    my ($self, $channel) = @_;

    return unless $channel->{join};
    print STDERR "Joining " . $channel->{name} , "\n";
    $self->{_irc}->yield(join => $channel->{name}, $channel->{password});
}

sub part {
    my ($self, $channel) = @_;

    return if $channel->{join};
    print STDERR "Parting " . $channel->{name} , "\n";
    $self->{_irc}->yield(part => $channel->{name});
}

#
# commands
#

sub command {
    my ($self, $channel, $nick, $what) = @_;
    return if $self->_is_bot($nick);

    my $network = $self->{_network};
    $what =~ s/(^\s+|\s+$)//g;
    foreach my $command (@{$self->{_commands}}) {
        my $executed = 0;
        eval {
            local $SIG{__DIE__} = sub { confess(@_) };
            $executed = $command->execute($network, $channel, $nick, $what)
        };
        if ($@) {
            print STDERR "$@\n";
            $self->respond($channel, $nick, sanatise_perl_error("$@"));
            $executed = 1;
        }
        last if $executed;
    }
}

sub say {
    my ($self, $channel, @text) = @_;
    foreach my $text (@text) {
        $self->{_irc}->yield(privmsg => $channel => $text);
        if (substr($channel, 0, 1) eq '#') {
            my $event = LogBot::Event->new(
                type => EVENT_PUBLIC,
                channel => $channel,
                nick => $self->{_network}->{nick},
                text => $text,
                time => now()->add(seconds => 1)->hires_epoch,
            );
            $self->_log_event($event);
        }
    }
}

sub respond {
    my ($self, $channel, $nick, @text) = @_;
    if (substr($channel, 0, 1) eq '#') {
        $text[0] = "$nick, " . $text[0];
    }
    $self->say($channel, @text);
}

#
# events
#

sub joined {
    my ($self, $channel, $nick) = @_;
    my $event = LogBot::Event->new(
        type => EVENT_JOIN,
        channel => $channel,
        nick => $nick,
    );
    $self->_log_event($event);
}

sub parted {
    my ($self, $channel, $nick, $text) = @_;
    my $event = LogBot::Event->new(
        type => EVENT_PART,
        channel => $channel,
        nick => $nick,
        text => $text,
    );
    $self->_log_event($event);
}

sub quit {
    my ($self, $nick, $text) = @_;
    # XXX there's no channel!
    #my $event = LogBot::Event->new(
    #    type => EVENT_QUIT,
    #    channel => $channel,
    #    nick => $nick,
    #    text => $text,
    #);
    #$self->_log_event($event);
}

sub public {
    my ($self, $channel, $nick, $what) = @_;
    my $event = LogBot::Event->new(
        type => EVENT_PUBLIC,
        channel => $channel,
        nick => $nick,
        text => $what,
    );
    $self->_log_event($event);
}

sub action {
    my ($self, $channel, $nick, $what) = @_;
    my $event = LogBot::Event->new(
        type => EVENT_ACTION,
        channel => $channel,
        nick => $nick,
        text => $what,
    );
    $self->_log_event($event);
}

#
# helpers
#

sub _log_event {
    my ($self, $event) = @_;
    my $channel = $self->{_network}->channel($event->{channel});
    return unless $channel;
    $channel->log_event($event);
}

sub _is_bot {
    my ($self, $nick) = @_;
    $nick = lc_irc($nick);
    return 1 if grep { $_ eq $nick } @{$self->{_network}{bots}};
    return 0;
}

1;
