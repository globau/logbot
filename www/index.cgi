#!/usr/bin/env perl

# the web ui needs to know where logbot is installed
# set this in apache with
# SetEnv HTTP_X_LIB_PATH /home/logbot/logbot/lib

use FindBin '$RealBin';
BEGIN {
    if ($ENV{HTTP_X_LIB_PATH}) {
        unshift @INC, $ENV{HTTP_X_LIB_PATH};
    } else {
        unshift @INC, "$RealBin/..";
    }
}
use LogBot::BP;

use CGI::Simple;
use DateTime;
use Date::Manip;
use Encode qw(decode);
use File::Slurp;
use HTTP::BrowserDetect;
use List::Util qw(any);
use LogBot::CGI;
use LogBot::Template;
use LogBot::Util;
use Mojo::JSON qw(encode_json);
use Mojo::Util qw(xml_escape url_escape);

my $conf_filename = 'logbot.conf';
foreach my $path (@INC) {
    next unless -e "$path/$conf_filename";
    $conf_filename = "$path/$conf_filename";
    last;
}
LogBot->init($conf_filename);

our $cgi = LogBot::CGI->instance;
our $config = LogBot->config;
our $vars = {
    cgi    => $cgi,
    config => $config,
    logbot => LogBot->instance,
};
$cgi->{vars} = $vars;

my $template = LogBot::Template->new();

parse_parameters();

if ($vars->{action} eq 'json') {
    print $cgi->header(-type => 'application/json', -charset => 'utf-8');

    $SIG{__DIE__} = sub {
        my $error = shift;
        print encode_json({ error => sanatise_perl_error($error) });
        exit;
    };
    die $vars->{error} . "\n" if exists $vars->{error};

    my $channel = $vars->{channel};
    my $request = $vars->{r};
    if ($request eq 'channel_data') {
        my $first = $channel->first_event;
        my $first_updated = $first
            ? $first->datetime->strftime('%d %b %Y %H:%M:%S')
            : '';
        my $last = $channel->last_message;
        my $last_updated = $last
            ? $last->datetime->strftime('%d %b %Y %H:%M:%S')
            : '';

        print encode_json({
            database_size => pretty_size($channel->database_size),
            first_updated => $first_updated,
            last_updated => $last_updated,
            event_count => commify($channel->event_count),
        });

    } elsif ($request =~ /^channel_plot_(hours|nicks)$/) {
        my $type = $1;
        my $network = $channel->{network}->{network};
        my $channel_name = $channel->{name};
        $channel_name =~ s/^#//;
        my $filename = $config->{data_path} . "/plot/$type/$network-$channel_name.json";
        if (!-e $filename) {
            $filename = $config->{data_path} . "/plot/$type/_empty.json";
        }
        print read_file($filename);

    } elsif ($request eq 'link_to') {
        print encode_json(link_to($channel));

    }

    exit;
}

if ($vars->{action} eq 'link_to') {
    my $link_to;
    eval {
        $link_to = link_to($vars->{channel});
    };
    if ($@) {
        $vars->{error} = $@;
        $vars->{action} = 'browse';
    } else {
        print "Location: " . $link_to->{url}, "\n\n";
        exit;
    }
}

# force queries from robots to a single date
my $is_robot = HTTP::BrowserDetect::robot() || $cgi->param('robot');
if ($is_robot) {
    if ($vars->{action} eq 'browse') {
        $vars->{end_date} = $vars->{start_date}->clone->add(days => 1);
        $vars->{h} = '';
        $vars->{j} = 0;
        $vars->{b} = 0;
    } elsif ($vars->{action} ne 'about') {
        $vars->{action} = 'browse';
        delete $vars->{run};
    }
}

# need special handling for the browse text format
my $is_text = $vars->{action} eq 'browse' && $vars->{t} eq 'text';

if ($is_text) {
    print $cgi->header(-charset => 'utf-8', -type => 'text/plain');
} else {
    print $cgi->header(-charset => 'utf-8');
}

if ($vars->{action} eq 'browse') {
    $cgi->{fields} = [qw(c s e j b h)];
} elsif ($vars->{action} eq 'search') {
    $cgi->{fields} = [qw(a c q ss se)];
}

$template->render('header.html', vars => $vars)
    unless $is_text;

if ($vars->{action} eq 'about') {

    $template->render('about.html', vars => $vars);

} else {

    if ($is_robot) {
        # give search crawlers a direct link to each log by date
        if (!$vars->{run}) {
            my $channel = $vars->{channel};
            my $first_event = $channel->first_event;
            my $last_event  = $channel->last_event;
            my $first_date = $first_event ? $first_event->datetime : now();
            my $last_date = $last_event ? $last_event->datetime->clone() : now();
            my $date = $first_date->clone()
                              ->truncate(to => 'day');
            $last_date = $last_date->truncate(to => 'day')
                                   ->add(days => 1)
                                   ->add(nanoseconds => -1);
            my @dates;
            while ($date < $last_date) {
                push @dates, $date->format_cldr('d MMM y');
                $date->add(days => 1);
            }
            $vars->{dates} = \@dates;
        }
        $template->render('robots.html', vars => $vars);
    } else {
        $template->render('tabs.html', vars => $vars)
            unless $is_text;
    }

    if ($vars->{run} && !$vars->{error}) {
        my %args = (
            channel => $vars->{channel},
        );

        if ($vars->{action} eq 'browse') {
            # browse
            $args{template}      = $vars->{t} ? 'browse-' . $vars->{t} : 'browse';
            $args{start_date}    = $vars->{start_date};
            $args{end_date}      = $vars->{end_date};
            $args{hilite}        = $vars->{h};
            $args{messages_only} = !$vars->{j};
            $args{empty_dates}   = !$is_text;
            $args{linkify}       = !$is_text;
            if ($vars->{b}) {
                $args{exclude_nicks} = $vars->{network}->{bots};
            }

        } else {
            # search
            $args{template}      = 'search';
            $args{start_date}    = $vars->{search_start_date};
            $args{end_date}      = $vars->{search_end_date};
            $args{hilite}        = $vars->{q};
            $args{messages_only} = 1;
            $args{empty_dates}   = 0;
            $args{linkify}       = 1;
            $args{limit}         = $config->{web}->{search_limit};
            if ($vars->{q} =~ s/<([^>]+)>//) {
                $args{nick} = $1;
            }
            $args{include_text} = $vars->{q};
        }

        show_events(%args);
    }
}

$template->render('footer.html')
    unless $is_text;

#

sub parse_parameters {

    # short-circuit default page

    if (!$ENV{QUERY_STRING} || $ENV{QUERY_STRING} eq '') {
        $vars->{action} = 'about';
        return;
    }

    # split network and channel

    my ($network_name, $channel_name);
    $channel_name = $cgi->param('c');
    if (!defined $channel_name || $channel_name eq '') {
        $network_name = $config->{web}->{default_network};
        $channel_name = $config->{web}->{default_channel};
    } elsif ($channel_name =~ /^([^#]+)(#.+)$/) {
        ($network_name, $channel_name) = ($1, $2);
    } else {
        $network_name = $config->{web}->{default_network};
        $channel_name = '#' . $channel_name unless $channel_name =~ /^#/;
    }

    # validate network

    my $network = LogBot->network($network_name);
    if (!$network) {
        $network = LogBot->network($config->{web}->{default_network});
    }
    $vars->{network} = $network;

    # validate channel

    my $channel = $network->channel($channel_name);
    if (!$channel || !($channel->{public} || $channel->{hidden})) {
        $vars->{error} = "Unsupported channel $channel_name";
        $vars->{action} = ($cgi->param('a') // '') eq 'json' ? 'json' : 'about';
        return;
    }
    $vars->{channel} = $channel;

    ($network_name, $channel_name) = ($network->{network}, $channel->{name});
    $vars->{c} = $network_name . $channel_name;

    # action

    my $action = $cgi->param('a');
    $action = '' if !defined($action) || ($action ne 'search' && $action ne 'json' && $action ne 'link_to');

    if ($action eq '') {
        delete $vars->{a};
        $vars->{action} = 'browse';

        # browse

        $vars->{run} = 1;
        $vars->{s}   = $cgi->param('s');
        $vars->{e}   = $cgi->param('e');
        $vars->{j}   = $cgi->param('j');
        $vars->{b}   = $cgi->param('b');
        $vars->{t}   = $cgi->param('t');

        # start date

        if ($cgi->param('s')) {
            my $start_time = UnixDate(lc($cgi->param('s')) . ' 00:00:00', '%s');
            unless (defined $start_time) {
                $vars->{error} = 'Invalid start date';
                return;
            }
            $vars->{start_date} = DateTime->from_epoch(epoch => $start_time);
        }

        # end date

        if ($cgi->param('e')) {
            my $end_time = UnixDate(lc($cgi->param('e')) . ' 23:59:59', '%s');
            unless (defined $end_time) {
                $vars->{error} = 'Invalid end date';
                return;
            }
            $vars->{end_date} = DateTime->from_epoch(epoch => $end_time);
        }

        # hilite (not in UI, for backwards compatibility)

        if (defined $cgi->param('h') && $cgi->param('h') ne '') {
            $vars->{h} = $cgi->param('h');
        } else {
            delete $vars->{h};
        }

        # boolen args

        if (defined $cgi->param('j')) {
            $vars->{j} = $cgi->param('j') eq '1' ? '1' : '0';
        }
        delete $vars->{j} unless $vars->{j};

        if (defined $cgi->param('b')) {
            $vars->{b} = $cgi->param('b') eq '1' ? '1' : '0';
        }
        delete $vars->{b} unless $vars->{b};

        # template

        $vars->{t} = '' unless $vars->{t} && ($vars->{t} eq 'min' || $vars->{t} eq 'text');

    } elsif ($action eq 'json') {
        $vars->{action} = 'json';

        # json data

        $vars->{r} = $cgi->param('r');

        # no need to prefill data for tabs

        return;

    } elsif ($action eq 'link_to') {
        $vars->{action} = 'link_to';
        return;

    } else {

        $vars->{a} = 'search';
        $vars->{action} = 'search';

        # search

        $vars->{q}  = $cgi->param('q');
        $vars->{ss} = $cgi->param('ss');
        $vars->{se} = $cgi->param('se');

        # query

        if (defined $cgi->param('q')) {
            my $query = $cgi->param('q');
            $query =~ s/(^\s+|\s+$)//g;
            if ($query ne '') {
                $vars->{run} = 1;
                $vars->{q} = $query;
            }
        }

        # start date

        if ($cgi->param('ss')) {
            my $start_time = UnixDate(lc($cgi->param('ss')) . ' 00:00:00', '%s');
            unless (defined $start_time) {
                $vars->{error} = 'Invalid start date';
                return;
            }
            $vars->{search_start_date} = DateTime->from_epoch(epoch => $start_time);
            $vars->{ss} = $vars->{search_start_date}->format_cldr('d MMM y');
        } else {
            delete $vars->{search_start_date};
            delete $vars->{ss};
        }

        # end date

        if ($cgi->param('se')) {
            my $end_time = UnixDate(lc($cgi->param('se')) . ' 23:59:59', '%s');
            unless (defined $end_time) {
                $vars->{error} = 'Invalid end date';
                return;
            }
            $vars->{search_end_date} = DateTime->from_epoch(epoch => $end_time);
            $vars->{se} = $vars->{search_end_date}->format_cldr('d MMM y');
        }

        # ensure start date < end date

        if ($vars->{search_start_date} &&
            $vars->{search_end_date} &&
            $vars->{search_start_date} > $vars->{search_end_date}
        ) {
            $vars->{search_end_date} = $vars->{search_start_date}
                                       ->clone
                                       ->truncate(to => 'day')
                                       ->add(days => 1)
                                       ->add(nanoseconds => -1);
        }

    }

    # we always want dates on the browse tab

    $vars->{start_date} ||= now()
                            ->truncate(to => 'day');
    $vars->{end_date}   ||= now()
                            ->truncate(to => 'day')
                            ->add(days => 1)
                            ->add(nanoseconds => -1);

    # don't allow browsing outside collected date ranges

    my $first_event = $channel->first_event;
    my $first_event_date = $first_event
        ? $first_event->datetime->truncate(to => 'day')
        : now()->truncate(to => 'day');
    $vars->{first_date} = $first_event_date;
    my $last_date = now()
                    ->truncate(to => 'day')
                    ->add(days => 1)
                    ->add(nanoseconds => -1);
    $vars->{last_date} = $last_date;

    if ($vars->{start_date} < $first_event_date) {
        $vars->{start_date} = $first_event_date;
    } elsif ($vars->{start_date} > $last_date) {
        $vars->{start_date} = $last_date;
    }

    if ($vars->{end_date} > $last_date) {
        $vars->{end_date} = $last_date;
    }

    # ensure start date < end date

    if ($vars->{start_date} > $vars->{end_date}) {
        $vars->{end_date} = $vars->{start_date}
                            ->clone
                            ->truncate(to => 'day')
                            ->add(days => 1)
                            ->add(nanoseconds => -1);
    }

    # don't allow massive date spans when browsing

    if ($vars->{action} eq 'browse' && $vars->{run}) {
        if ($vars->{start_date}->delta_days($vars->{end_date})->in_units('days') > MAX_BROWSE_DAY_SPAN) {
            $vars->{error} = 'You cannot browse dates greater than ' . MAX_BROWSE_DAY_SPAN . ' days apart.';
            return;
        }
    }

    # format dates for display

    $vars->{s} = $vars->{start_date}->format_cldr('d MMM y');
    $vars->{e} = $vars->{end_date}->format_cldr('d MMM y');

    # we always want a default search start date

    if ($vars->{action} ne 'search') {
        $vars->{search_start_date} = now()
                                     ->truncate(to => 'day')
                                     ->add(months => -1);
        $vars->{ss} = $vars->{search_start_date}->format_cldr('d MMM y');
    }
}

#

sub show_events {
    my (%args) = @_;

    my $template_dir = $args{template};
    $template->render("$template_dir/header.html", vars => $vars);

    # build filters

    my %filter = (
        order => 'time',
    );
    if ($args{start_date}) {
        $filter{date_after} = $args{start_date}->epoch;
    }
    if ($args{end_date}) {
        $filter{date_before} = $args{end_date}->epoch;
    }
    if ($args{include_text}) {
        $filter{include_text} = [ $args{include_text} ];
    }
    if ($args{nick}) {
        $filter{nick} = $args{nick};
    }
    if ($args{messages_only}) {
        $filter{events} = [ EVENT_PUBLIC, EVENT_ACTION ];
    }
    if ($args{limit}) {
        $filter{limit_last} = $args{limit};
    }
    if ($args{exclude_nicks}) {
        $filter{exclude_nicks} = $args{exclude_nicks};
    }
    if ($cgi->param('debug')) {
        $filter{debug_sql} = 1;
    }

    # init hiliting

    my $hilite;
    if (exists $args{hilite} && defined($args{hilite})) {
        $hilite = $args{hilite};
        $hilite =~ s/</\000/g;
        $hilite =~ s/>/\001/g;
        $hilite =~ s/&/\002/g;
    }

    # init date tracking and counting

    my $current_date;
    if ($args{start_date}
        && $args{end_date}
        && $args{start_date}->ymd('') eq $args{end_date}->ymd('')
    ) {
        $current_date = 0;
    } elsif (!$args{start_date}) {
        $current_date = 0;
    } else {
        $current_date = $args{start_date}
                        ->clone
                        ->truncate(to => 'day')
                        ->add(days => -1);
    }
    my $today_date = now()->truncate(to => 'day');
    my $last_date = $vars->{last_date};
    my $first_date = $vars->{first_date};

    my $last_event = 0;
    my $event_count = 0;

    # hit the db

    $args{channel}->browse(
        %filter,
        callback    => sub {
            my $event = shift;
            $last_event = $event;
            $event_count++;

            # new date header

            if (!$current_date || $event->date ne $current_date) {

                if ($args{empty_dates}) {

                    # show day even if there's no messages

                    if ($current_date) {
                        $current_date->add(days => 1);
                        while ($current_date < $event->date) {
                            render_date("$template_dir/date.html", $current_date, $first_date, $last_date);
                            $template->render("$template_dir/empty.html");
                            $current_date->add(days => 1);
                        }
                    }

                }

                # date header

                render_date("$template_dir/date.html", $event->date, $first_date, $last_date);
                $current_date = $event->date;
            }

            # linkify text
            if ($args{linkify}) {
                if (defined $hilite) {
                    $event->{text} = hilite($event->{text}, $hilite);
                } else {
                    $event->{text} = linkify(xml_escape($event->{text}));
                }
            }

            $event->{text} = decode('UTF-8', $event->{text});
            $vars->{bot} = any { $event->{nick} eq $_ } @{ $vars->{network}->{bots} };

            $template->render("$template_dir/content.html", vars => $vars, event => $event);

            return 1;
        },
    );

    if ($args{empty_dates}) {

        # show empty days after the last found event
        # this also duplicates the header for the last date if there were any events

        if ($current_date) {
            $current_date->add(days => 1);
        } else {
            $current_date = $args{start_date}->clone->truncate(to => 'day');
        }
        my $trailing_dates = 0;
        while ($current_date <= $args{end_date}) {
            last if $current_date > $today_date;
            $trailing_dates = 1;
            render_date("$template_dir/date.html", $current_date, $first_date, $last_date);
            $template->render("$template_dir/empty.html");
            $current_date->add(days => 1);
        }

        # if we output nothing (such as all dates are in the future), show something
        if (!$trailing_dates && !$last_event) {
            $current_date = $args{start_date}->clone->truncate(to => 'day');
            render_date("$template_dir/date.html", $current_date, $first_date, $last_date);
            $template->render("$template_dir/empty.html");
        }
    }

    # show footer date

    if ($current_date) {
        $current_date->add(days => -1);
        if ($last_event
            && $current_date->ymd() eq $last_event->datetime->ymd()
        ) {
            render_date("$template_dir/date.html", $current_date, $first_date, $last_date);
        }
    }

    $vars->{last_event}  = $last_event;
    $vars->{event_count} = $event_count;
    $template->render("$template_dir/footer.html", vars => $vars);
}

sub render_date {
    my ($file, $date, $first_date, $last_date) = @_;

    my $prev = $date->clone->add(days => -1);
    $prev = undef if $prev < $first_date;

    my $next = $date->clone->add(days => 1);
    $next = undef if $next > $last_date;

    $template->render(
        $file,
        date => $date,
        prev => $prev,
        next => $next,
    );
}

#

sub linkify {
    # XXX move to util?
    my ($value, $rs_href) = @_;
    $rs_href ||= sub { $_[0] };

    # munge email addresses
    $value =~ s#([a-zA-Z0-9\.-]+)\@(([a-zA-Z0-9\.-]+\.)+[a-zA-Z0-9\.-]+)#$1\%$2#g;

    unless ($value =~ s#&lt;(https?://.+?)&gt;#'&lt;<a href="' . $rs_href->($1) . '" target="_blank">' . shorten_url($1) . '</a>&gt;'#ge) {
        $value =~ s#(https?://[^\s\b,]*[^\s\b,.?!;)])#'<a href="' . $rs_href->($1) . '" target="_blank">' . shorten_url($1) . '</a>'#ge;
    }

    # bugzilla urls
    $value =~ s#(\bbug\s+(\d+))#<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=$2" target="_blank">$1</a>#gi;
    $value =~ s#(\battachment\s+(\d+))#<a href="https://bugzilla.mozilla.org/attachment.cgi?id=$2&action=edit" target="_blank">$1</a>#gi;

    return $value;
}

sub hilite {
    # XXX move to util?
    my ($value, $hilite) = @_;

    $value =~ s/</\000/g;
    $value =~ s/>/\001/g;
    $value =~ s/&/\002/g;

    $value = xml_escape($value);
    $value =~ s#($hilite)#\003$1\004#goi;

    $value =~ s/\000/&lt;/g;
    $value =~ s/\001/&gt;/g;
    $value =~ s/\002/&amp;/g;

    $value = linkify(
        $value,
        sub {
            my $value = shift;
            $value =~ s/[\003\004]//g;
            return $value;
        }
    );

    $value =~ s#\003#<span class="hilite">#g;
    $value =~ s#\004#</span>#g;

    return $value;
}


sub link_to {
    my ($channel) = @_;

    my $nick = $cgi->param('n') // die "nick required in param 'n'\n";
    my $time = $cgi->param('t') // die "time required in param 't'\n";
    die "invalid time\n" if $time =~ /\D/;

    my @events;
    $channel->database->query(
        event => EVENT_PUBLIC,
        nick => $nick,
        date_before => $time + 5,
        date_after => $time - 5,
        callback => sub { push @events, $_[0] },
    );

    @events = sort { abs($time - $a->{time}) <=> abs($time - $b->{time}) } @events;
    die "failed to find message\n" unless @events;
    my $event = $events[0]->to_ref;
    delete $event->{type};

    my $url = $config->{web}->{url} . '?';

    my $network = $channel->{network}->{network};
    my $c = '';
    if ($network ne $config->{web}->{default_network}) {
        $c = $network;
    }
    if ($channel->{name} ne $config->{web}->{default_channel}) {
        $c .= $channel->{name};
    }
    if ($c) {
        $url .= 'c=' . url_escape($c);
    }

    my $s = DateTime->from_epoch(epoch => $time)->truncate(to => 'day')->ymd('');
    $url .= '&s=' . $s. '&e=' . $s;

    $url .= '#c' . $event->{id};

    return {
        event => $event,
        url   => $url,
    };
}
