package LogBot::Web::Util;
use local::lib;
use v5.10;
use strict;
use warnings;
use utf8;

use Date::Parse qw( str2time );
use DateTime ();
use Encode qw ( decode );
use File::Basename qw( basename );
use LogBot::Database qw( dbh );
use LogBot::Util qw( nick_is_bot normalise_channel time_to_ymd ymd_to_time );
use LogBot::Web::Colour qw( nick_hash );
use Module::Load qw( load );
use Mojo::Path ();
use Mojo::URL  ();
use Mojo::Util qw( html_unescape url_escape xml_escape );
use Readonly;
use URI::Find ();

our @EXPORT_OK = qw(
    render_init
    rewrite_old_urls
    url_for_channel irc_host
    channel_from_param date_from_param
    linkify munge_emails
    preprocess_event
    channel_topics
);
use parent 'Exporter';

sub render_init {
    my ($path) = @_;
    foreach my $file (glob($path . '/lib/LogBot/Web/*.pm')) {
        next if basename($file) =~ /^(?:Colour|Util)\.pm$/;
        load($file);
    }
}

sub rewrite_old_urls {
    my ($c) = @_;
    my $network_channel = $c->req->query_params->param('c') || return;

    my ($network, $channel);
    if ($network_channel =~ /^([^#]+)(#.+)/) {
        ($network, $channel) = ($1, $2);
    } else {
        ($network, $channel) = ('mozilla', $network_channel);
    }
    $channel = normalise_channel($channel);

    my $path        = Mojo::Path->new();
    my $url         = $c->req->url->to_abs();
    my $default_url = Mojo::URL->new($c->stash('config')->{url});
    (my $default_host = $default_url->host) =~ s/^[^.]+\.//;

    # map network to subdomain
    if ($url->host ne 'localhost' && $url->host ne '127.0.0.1') {
        $url->host($network . '.' . $default_host);
    }

    # map port
    $url->port($default_url->port);

    # find action
    my $req_query = $c->req->query_params;
    my $a         = $req_query->param('a') // 'browse';
    my $q         = $req_query->param('q') // '';

    if ($a eq 'browse') {

        # check for redirects that require a date lookup
        if (my $comment_id = $req_query->param('cid')) {
            if ($comment_id =~ s/^c(\d+)$/$1/) {
                my $dbh = dbh($c->stash('config'), cached => 1);
                my $time = $dbh->selectrow_array('SELECT time FROM logs WHERE channel = ? AND old_id = ? LIMIT 1',
                    undef, $channel, $comment_id);
                if ($time) {
                    $req_query->param('s', time_to_ymd($time));
                }
            }
            $url->fragment($req_query->param('cid'));
            $req_query->param('cid', undef);
        }

        # c=mozilla%23developers&s=8+Jul+2017&e=8+Jul+2017
        # note: multi-date ranges are no longer supported
        push @{$path}, substr($channel, 1);
        if (my $time = str2time($req_query->param('s') // '')) {
            push @{$path}, time_to_ymd($time);
        }

        $url->query('');

    } elsif ($a eq 'search' && $q ne '') {

        # a=search&c=mozilla%23developers&q=glob&ss=8+Jun+2017&se=

        my %query = (q => $q, ch => $channel, ft => 'n');

        if (my $time = str2time($req_query->param('ss') // '')) {
            $query{f} = time_to_ymd($time, '-');
            $query{w} = 'c';
        }
        if (my $time = str2time($req_query->param('se') // '')) {
            $query{t} = time_to_ymd($time, '-');
            $query{w} = 'c';
        }

        $url->query(%query);
    }

    $url->path($path);
    return $url->to_string;
}

sub url_for_channel {
    my %params = @_;
    my @path = url_escape(substr($params{channel}, 1));
    if ($params{date}) {
        push @path, ref($params{date}) ? $params{date}->ymd('') : $params{date};
    }
    return '/' . join('/', @path) . ($params{id} ? '#c' . $params{id} : '');
}

sub irc_host {
    my ($config, %params) = @_;

    my $url = $config->{irc}->{host};

    if ($url =~ s/^ssl:// && $params{url}) {
        $url = 'ircs://' . $url;
        $url =~ s/:6697$//;
    } elsif ($params{url}) {
        $url = ($url =~ /:6697$/ ? 'ircs' : 'irc') . '://' . $url;
        $url =~ s/:6667$//;
    }

    $url =~ s/:\d+$// unless $params{url};
    $url .= '/' if $params{url} || $params{channel};
    $url .= substr($params{channel}, 1) if $params{channel};

    return $url;
}

sub channel_from_param {
    my ($c)     = @_;
    my $config  = $c->stash('config');
    my $channel = normalise_channel($c->param('channel'));

    if (!exists $config->{channels}->{$channel}
        || ($config->{channels}->{$channel}->{disabled} && !$config->{channels}->{$channel}->{web_only}))
    {
        my $message = "The channel $channel is not logged.";
        $c->res->code(404);
        $c->res->message($message);
        LogBot::Web::Index::render($c, { error => $message });
        return undef;
    }

    return $channel;
}

sub date_from_param {
    my ($c) = @_;

    # find date
    my $time = ymd_to_time($c->param('date')) // time();
    my $date = DateTime->from_epoch(epoch => $time)->truncate(to => 'day');

    # difficult to log future events
    return $date > $c->stash('today') ? undef : $date;
}

sub linkify {
    my ($value) = @_;

    # linkify urls
    my $finder = URI::Find->new(
        sub {
            my ($uri, $orig_uri) = @_;
            return '<a href="' . $uri . '" rel="nofollow">' . shorten_url($orig_uri) . '</a>';
        }
    );
    $finder->find(\$value, \&xml_escape);

    # munge email addresses
    $value = munge_emails($value);

    # linkify "bug NNN"
    $value =~ s{(\bbug\s+(\d+))}{<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=$2">$1</a>}gi;

    # linkify "servo: merge #NNN"
    $value =~ s{(\bservo: Merge \#(\d+))}{<a href="https://github.com/servo/servo/pull/$2">$1</a>}gi;

    return $value;
}

sub _munge_domain {
    my ($domain) = @_;
    $domain =~ s/(.)(?:[^.]+\.|.+$)/$1/g;
    return $domain;
}

sub munge_emails {
    my ($value) = @_;
    $value =~ s{([a-zA-Z0-9\.-]+)\@(([a-zA-Z0-9\.-]+\.)+[a-zA-Z0-9\.-]+)}{$1 . '⊙' . _munge_domain($2)}ge;
    return $value;
}

# trims the middle of a url, or generates nice short version
sub shorten_url {
    my ($value) = @_;

    # protocol and www is noise
    $value =~ s{^https?://(?:www\.)?}{};
    $value =~ s{/$}{};

    # bmo
    $value =~ s{^bugzilla\.mozilla\.org/show_bug\.cgi\?id=(\d+)}{bugzilla.mozilla.org/$1}
        && return $value;

    # hgmo
    $value =~ s{^hg\.mozilla\.org/(?:(?:integration|releases)/)?([^/]+)/rev/([0-9a-f]+)$}{$1/$2}
        && return $value;
    $value =~ s{^hg\.mozilla\.org/(?:[^/]+/)?([^/]+)/pushloghtml\?startID=(\d+)&endID=(\d+)}{$1 pushlog:$2-$3}
        && return $value;

    # github
    $value =~ s{^github\.com/([^/]+/[^/]+)/(?:issues|pull)/(\d+)}{$1 #$2}
        && return $value;
    $value =~ s{^github\.com/([^/]+/[^/]+)/commit/([a-z0-9]{7})(?:[a-z0-9]{33})?}{$1 $2}
        && return $value;

    # treeherder
    $value =~ s{^treeherder\.mozilla\.org/#/jobs\?repo=([^&]+)&amp;revision=([0-9a-f]+)$}{treeherder $1:$2}
        && return $value;

    # shorten in the middle

    # avoid unescaping if we're clearly under the limit
    return $value if length($value) < 70;

    # need to unescape string to avoid splitting entities
    my $unescaped = html_unescape($value);
    return $value if length($unescaped) < 70;

    # trim the middle of the string
    my $diff = length($unescaped) - 70;
    substr($unescaped, (length($unescaped) / 2) - ($diff / 2), $diff, "\0");
    $value = xml_escape($unescaped);
    $value =~ s/\0/&hellip;/;
    return $value;
}

sub preprocess_event {
    my ($config, $event, $nick_hashes) = @_;
    $event->{hhss} = sprintf('%02d:%02d', (localtime($event->{time}))[2, 1]);
    $event->{text} = linkify(decode('UTF-8', $event->{text}));
    $event->{text} =~ s/^\s+$/\xa0/;
    if (nick_is_bot($config, $event->{nick})) {
        $event->{bot}  = 1;
        $event->{hash} = '0';
    } else {
        $event->{bot}                    = 0;
        $event->{hash}                   = nick_hash($event->{nick});
        $event->{text}                   = addressed_nick($event->{text}, $nick_hashes);
        $nick_hashes->{ $event->{hash} } = 1;
    }
}

sub addressed_nick {
    my ($text, $nick_hashes) = @_;
    if ($text =~ s/^([a-zA-Z0-9_|-]+):\s+//) {
        my $hash = nick_hash($1);
        $text = '<span class="nc" data-hash="' . $hash . '">' . $1 . '</span>: ' . $text;
        $nick_hashes->{$hash} = 1;
    }
    return $text;
}

sub channel_topics {
    my ($config) = @_;
    my $dbh = dbh($config, cached => 1);
    return { map { $_->[0] => decode('UTF-8', $_->[1]) }
            @{ $dbh->selectall_arrayref('SELECT channel,topic FROM topics') } };
}

1;
