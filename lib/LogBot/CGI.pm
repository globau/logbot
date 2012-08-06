package LogBot::CGI;

use strict;

use base 'CGI::Simple';

use CGI::Session;

my $_instance;
sub instance {
    $_instance ||= shift->_new();
    return $_instance;
}

sub _new {
    my ($invocant, @args) = @_;
    my $class = ref($invocant) || $invocant;
    my $self = $class->SUPER::new(@args);
    return $self;
}

sub init_session {
    my ($self) = @_;
    return if exists $self->{session};
    my $path = LogBot->config->{data_path} . '/sessions';
    $self->{session} = CGI::Session->new(
        'driver:file;serializer:default;id:md5',
        $self,
        { Directory => $path }
    );
    $self->{session}->expire('+3d');
}

my $_seen_header = 0;
sub header {
    my $self = shift;
    return '' if $_seen_header;
    $_seen_header = 1;
    if (exists $self->{session}) {
        my $cookie = $self->cookie(
            -name  => $self->{session}->name,
            -value => $self->{session}->id,
        );
        push @_, -cookie => $cookie;
    }
    return $self->SUPER::header(@_);
}

sub logbot_url {
    my ($self, %args) = @_;
    my %query = ();
    my $vars = $self->{vars} || {};
    my $fields = $self->{fields} || [];

    # shortcuts

    if (exists $args{browse}) {
        # browse to a specific date
        my $date = $args{browse};
        if (ref($date)) {
            $date = $date->format_cldr('d MMM y');
        }
        $fields = [qw(c s e j b h)];
        $query{a} = 'browse';
        $query{c} = $self->{vars}->{c};
        $query{s} = $date;
        $query{e} = $date;
        $query{h} = $args{hilite} if exists $args{hilite};
        if ($self->{vars}->{raw}) {
            push @$fields, 'raw';
            $query{raw} = $self->{vars}->{raw};
        }
    }

    # build query

    my @query;
    foreach my $name (@$fields) {
        next unless exists($vars->{$name}) || exists $query{$name};
        my $value = exists $query{$name} ? $query{$name} : $vars->{$name};
        next if $name eq 'a' && $value eq 'browse';
        push @query, $self->url_encode($name) . '=' . $self->url_encode($value);
    }
    return '?' . join('&amp;', @query);
}

1;
