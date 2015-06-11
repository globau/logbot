package LogBot::Event;
use LogBot::BP;

use base 'LogBot::Base';

use DateTime;

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
    if (defined $self->{text}) {
        # remove irc colours
        $self->{text} =~ s/\cC\d{1,2}(?:,\d{1,2})?//g;
        $self->{text} =~ s/(?:\c[CBIURO])//g;
        $self->{text} =~ tr/\x02\x0f\x1f//d;
    } else {
        $self->{text} = '';
    }
    $self->{id} ||= 0;
    $self->{channel} = canon_channel($self->{channel});
    $self->{time} ||= now()->hires_epoch;

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
    if ($self->{type} == EVENT_PUBLIC) {
        $template = '[%s] <%s> %s';
    } elsif ($self->{type} == EVENT_JOIN) {
        $template = '[%s] *** %s (%s) has joined %s';
    } elsif ($self->{type} == EVENT_PART) {
        $template = '[%s] *** %s (%s) has left %s';
    } elsif ($self->{type} == EVENT_QUIT) {
        $template = '[%s] *** %s has quit IRC [%s]';
    } elsif ($self->{type} == EVENT_ACTION) {
        $template = '[%s] * %s %s';
    }
    return sprintf($template, simple_date_string($self->datetime), $self->{nick}, $self->{text} || '', $self->{channel});
}

sub to_ref {
    my ($self) = @_;
    my $ref = {};
    foreach my $field (qw( id type time channel nick text )) {
        $ref->{$field} = $self->{$field};
    }
    return $ref;
}

sub log_string {
    my ($self) = @_;

    my $template;
    if ($self->{type} == EVENT_PUBLIC) {
        $template = '%s <%s> %s';
    } elsif ($self->{type} == EVENT_JOIN) {
        $template = '%s *** %s (%s) has joined %s';
    } elsif ($self->{type} == EVENT_PART) {
        $template = '%s *** %s (%s) has left %s';
    } elsif ($self->{type} == EVENT_QUIT) {
        $template = '%s *** %s has quit IRC [%s]';
    } elsif ($self->{type} == EVENT_ACTION) {
        $template = '%s * %s %s';
    }
    return sprintf($template, $self->datetime, $self->{nick}, $self->{text} || '', $self->{channel});
}

1;
