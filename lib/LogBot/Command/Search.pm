package LogBot::Command::Search;

use strict;
use warnings;

use LogBot::Config;
use LogBot::Constants;
use LogBot::Util;
use IRC::Utils ':ALL';

use constant MAX_RESULTS_PUBLIC  => 3;
use constant MAX_RESULTS_PRIVATE => 10;
use constant MAX_RESULTS_UPPER   => 20;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->{bot} = shift;
    return $self;
}

sub execute {
    my ($self, $network, $respond_channel, $nick, $command) = @_;

    my $is_public = $respond_channel =~ /^#/;
    my $search_channel = $respond_channel;
    my $search_nick = '';
    my $limit = $is_public ? MAX_RESULTS_PUBLIC : MAX_RESULTS_PRIVATE;

    my @query = split(/\s+/, $command);
    while (scalar @query) {
        if ($query[0] =~ /^#(.+)/) {
            $search_channel = $1;
            shift @query;
        } elsif ($query[0] =~ /^\<([^\>]+)\>$/) {
            $search_nick = $1;
            shift @query;
        } else {
            last;
        }
    }
    my $query = join(' ', @query);

    if ($search_channel eq '') {
        return if $is_public;
        $self->{bot}->say(
            $respond_channel,
            'You must specify a channel to search',
            'Syntax: #channel [<nick>] query'
        );
        return;
    }

    $search_channel = canon_channel($search_channel);
    my $channel = $network->channel($search_channel);
    if (!$channel) {
        $self->{bot}->respond(
            $respond_channel, $nick,
            "Unsupported channel $search_channel"
        );
        return;
    }

    if ($search_nick eq '' && $query eq '') {
        return if $is_public;
        $self->{bot}->say(
            $respond_channel,
            'You must specify a query string or a nick',
            'Syntax: #channel [<nick>] query'
        );
        return;
    }

    $search_nick = lc_irc($search_nick);
    my $bot_nick = $network->config->{nick};

    my @results;
    $channel->browse(
        nick => $search_nick,
        exclude_nicks => [ $bot_nick ],
        exclude_text => [ "$bot_nick,", "$bot_nick:" ],
        include_text => [ $query ],
        order => 'time DESC',
        limit => MAX_RESULTS_UPPER + 1,
        events => [ EVENT_PUBLIC, EVENT_ACTION ],
        callback => sub {
            my $event = shift;
            push @results, $event;
            return 1;
        },
    );
    my $count = scalar @results;
    pop @results while (scalar @results) > $limit;
    @results = map { $_->to_string } @results;

    if ($count > MAX_RESULTS_UPPER) {
        unshift @results,
            sprintf(
                "found more than %d results, showing %s",
                MAX_RESULTS_UPPER, 
                $limit
            );

    } else {
        unshift @results,
            sprintf(
                "found %d result%s%s",
                $count,
                $count == 1 ? '' : 's',
                $count > $limit ? " showing $limit" : ''
            );
    }

    $self->{bot}->respond($respond_channel, $nick, @results);
    return 1;
}

1;

