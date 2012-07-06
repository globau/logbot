package LogBot::Event;

use strict;
use warnings;
use feature qw(switch);

use DateTime;
use LogBot::Constants;
use LogBot::Util;

use fields qw(
    id
    type
    time
    channel
    nick
    text
    _datetime
    _date
);

use overload (
    '""' => 'to_string',
);

sub new {
    my $class = shift;
    my $self = fields::new($class);

    # TODO check to ensure all fields are provided
    # 'time' is optional
    my (%args) = @_;
    foreach my $field (qw(id type time channel nick text)) {
        $self->{$field} = $args{$field};
    }
    $self->{id} ||= 0;
    $self->{channel} = canon_channel($self->{channel});
    $self->{time} ||= now()->hires_epoch;
    $self->{text} = '' unless defined $self->{text};

    return $self;
}

sub datetime {
    my ($self) = @_;
    if (!exists $self->{_datetime}) {
        $self->{_datetime} = DateTime->from_epoch(
            epoch => $self->{time},
            time_zone => 'UTC',
        );
    }
    return $self->{_datetime};
}

sub date {
    my ($self) = @_;
    if (!exists $self->{_date}) {
        $self->{_date} = $self->datetime->clone->truncate(to => 'day');
    }
    return $self->{_date};
}

sub time_string {
    my ($self) = @_;
    return $self->datetime->hms();
}

sub to_string {
    my ($self) = @_;

    my $template;
    given($self->{type}) {
        when(EVENT_PUBLIC) { $template = '%s <%s> %s' }
        when(EVENT_JOIN)   { $template = '%s *** %s (%s) has joined %s' }
        when(EVENT_PART)   { $template = '%s *** %s (%s) has left %s' }
        when(EVENT_QUIT)   { $template = '%s *** %s has quit IRC [%s]' }
        when(EVENT_ACTION) { $template = '%s * %s %s' }
    }
    return sprintf($template, simple_date_string($self->datetime), $self->{nick}, $self->{text} || '', $self->{channel});
}

sub log_string {
    my ($self) = @_;

    my $template;
    given($self->{type}) {
        when(EVENT_PUBLIC) { $template = '%s <%s> %s' }
        when(EVENT_JOIN)   { $template = '%s *** %s (%s) has joined %s' }
        when(EVENT_PART)   { $template = '%s *** %s (%s) has left %s' }
        when(EVENT_QUIT)   { $template = '%s *** %s has quit IRC [%s]' }
        when(EVENT_ACTION) { $template = '%s * %s %s' }
    }
    return sprintf($template, $self->datetime, $self->{nick}, $self->{text} || '', $self->{channel});
}

1;
