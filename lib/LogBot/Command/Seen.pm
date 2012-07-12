package LogBot::Command::Seen;

use strict;
use warnings;

use DateTime;
use LogBot::Util;
use Time::Duration;
use Time::Local;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->{bot} = shift;
    return $self;
}

sub execute {
    my ($self, $network, $respond_channel, $nick, $command) = @_;
    return unless $command =~ /^seen\s+(.+)/i;
    my $seen_nick = $1;

    # check for silliness

    if ($seen_nick eq $nick) {
        $self->{bot}->respond(
            $respond_channel, $nick,
            sprintf('%s: <%s> %s', 'now', $nick, $command)
        );
        return 1;
    }

    # check current channel for last seen

    my $event = $network->channel($respond_channel)->seen($seen_nick);

    # check all other channels
    if (!$event) {
        my @events;
        foreach my $channel ($network->channels) {
            next if $channel->{name} eq $respond_channel;
            my $e = $channel->seen($seen_nick);
            push @events, $e if $e;
        }
        if (@events) {
            @events = sort { $b->{time} <=> $a->{time} } @events;
            $event = $events[0];
        }
    }

    if (!$event) {
        $self->{bot}->respond($respond_channel, $nick, "never seen '$seen_nick'");

    } else {
        my $ago = ago(now()->hires_epoch - $event->{time});

        if ($event->{channel} eq $respond_channel) {
            $self->{bot}->respond(
                $respond_channel, $nick,
                sprintf('%s: <%s> %s', $ago, $event->{nick}, $event->{text})
            );
        } else {
            $self->{bot}->respond(
                $respond_channel, $nick,
                sprintf('%s: <%s> %s %s', $ago, $event->{nick}, $event->{channel}, $event->{text})
            );
        }
    }

    return 1;
}

1;
