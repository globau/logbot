package LogBot::Channel;

use strict;
use warnings;

use base 'LogBot::Base';

use LogBot::Constants;
use LogBot::Database;
use LogBot::Util;

use fields qw(
    network
    name
    password
    public
    hidden
    in_channel_search
    log_events
    join
    _database
);

use constant IMUTABLE_FIELDS => qw(
    network
    name
);

sub new {
    my ($class, %args) = @_;
    my $self = fields::new($class);
    foreach my $field (keys %args) {
        $self->{$field} = $args{$field};
    }
    return $self;
}

sub database {
    my ($self) = @_;
    $self->{_database} ||= LogBot::Database->new($self->{network}, $self->{name});
    return $self->{_database};
}

sub reconfigure {
    my ($self, %args) = @_;

    my @changed = $self->update_from_args([ IMUTABLE_FIELDS ], \%args);

    if (grep { $_ eq 'join'} @changed) {
        if ($self->{join}) {
            LogBot->action(ACTION_CHANNEL_JOIN, $self->{network}, $self);
        } else {
            LogBot->action(ACTION_CHANNEL_PART, $self->{network}, $self);
        }
    }
}

sub log_event {
    my ($self, $event) = @_;
    my $type = $event->{type};
    if (
        ($type == EVENT_JOIN || $type == EVENT_PART || $type == EVENT_QUIT)
        && (!$self->{log_events})
    ) {
        return;
    }
    $self->database->log_event($event);
}

sub search {
    my ($self, %args) = @_;
    return [] unless $self->{in_channel_search};
    return $self->database->search(%args);
}

sub seen {
    my ($self, $nick) = @_;
    return unless $self->{public};
    return $self->database->seen($nick);
}

sub browse {
    my ($self, %args) = @_;
    return $self->database->query(%args);
}

sub database_size {
    my ($self) = @_;
    return $self->database->size;
}

sub event_count {
    my ($self) = @_;
    return $self->database->event_count;
}

sub first_event {
    my ($self) = @_;

    my $event = $self->database->meta('first_event');
    if (!$event) {
        my @events;
        $self->database->query(
            order    => 'time ASC',
            limit    => '1',
            callback => sub { push @events, shift },
        );
        $event = @events ? $events[0] : undef;
        $self->database->meta('first_event', $event);
    }
    return $event;
}

sub last_event {
    my ($self) = @_;
    my @events;
    $self->database->query(
        order    => 'time DESC',
        limit    => '1',
        callback => sub { push @events, shift }, 
    );
    return @events ? $events[0] : undef;
}

sub last_message {
    my ($self) = @_;
    my @events;
    $self->database->query(
        events   => [ EVENT_PUBLIC, EVENT_ACTION ],
        order    => 'time DESC',
        limit    => '1',
        callback => sub { push @events, shift }, 
    );
    return @events ? $events[0] : undef;
}

1;
