package LogBot::Database;

use strict;
use warnings;

use base 'LogBot::Base';

use LogBot;
use LogBot::Constants;
use LogBot::Util;
use LogBot::Event;
use DBI;
use DBD::SQLite;

#

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);

    my $network = shift;
    die "missing network" unless $network;
    $network = $network->{network} if ref($network);
    $network = lc($network);
    $network =~ s/[^a-z1-9_\.-]/_/g;
    $self->{network} = $network;

    my $channel = canon_channel(shift);
    die "missing channel" unless $channel;
    $self->{channel} = $channel;
    $self->{filename} = $self->_filename($channel);
    $self->connect($channel);

    return $self;
}

sub connect {
    my ($self, $channel) = @_;

    my $filename = $self->{filename};
    my $dbh = DBI->connect(
        "DBI:SQLite:$filename", '', '', { 
            PrintError => 0, 
            RaiseError => 1,
            sqlite_use_immediate_transaction => 1,
    });

    $dbh->do("CREATE TABLE IF NOT EXISTS logs(time INTEGER, nick VARCHAR, event INTEGER, data VARCHAR)");
    $dbh->do("CREATE INDEX IF NOT EXISTS idx_time ON logs(time)");
    $dbh->do("CREATE INDEX IF NOT EXISTS idx_data ON logs(data)");

    $dbh->do("CREATE TABLE IF NOT EXISTS logs_meta(name INTEGER, id INTEGER)");
    $dbh->do("CREATE INDEX IF NOT EXISTS idx_meta ON logs_meta(name)");

    $self->{dbh} = $dbh;
}

sub _lazy_execute {
    my ($self, $callback) = @_;

    # execute inserts in the background, to ensure locks held by the web pages
    # don't block the bot from responding to pings from the irc server and
    # getting disconnected

    $SIG{CHLD} = 'IGNORE';
    my $pid = fork();
    if (defined($pid) && $pid == 0) {

        my $error_count = 0;
        my $success = 0;
        while (!$success) {
            eval {
                # we need to reconnect to the database as sqlite handles shouldn't be
                # used across forks
                $self->connect();

                $callback->($self->{dbh});
                $success = 1;
            };
            if ($@) {
                my $error = "$@";
                $error_count++;
                if ($error_count > 100) {
                    warn "$error\n";
                    return;
                } else {
                    sleep(4);
                }
            }
        }
        exit(0);
    }
}

sub log_event {
    my ($self, $event) = @_;

    $self->_lazy_execute(sub {
        my $dbh = shift;
        $dbh->do(
            "INSERT INTO logs(time,nick,event,data) VALUES (?,?,?,?)",
            undef,
            $event->{time},
            $event->{nick},
            $event->{type},
            $event->{text}
        );
    });
}

sub query {
    my ($self, %args) = @_;
    my @results = ();
    my $dbh = $self->{dbh};

    $args{callback}
        || die "no callback passed to LogBot::Database::search()\n";

    my $fields = "rowid,time,nick,event,data";

    my $sql = "SELECT $fields FROM logs WHERE ";
    my @where;

    if ($args{events}) {
        push @where, "(event IN (" . join(',', @{$args{events}}) . "))";
    }

    if ($args{exclude_nicks}) {
        foreach my $nick (@{$args{exclude_nicks}}) {
            push @where, "(LOWER(nick) <> " . $dbh->quote(trim($nick)) . ")";
        }
    }

    if ($args{nick}) {
        my $nick = $dbh->quote(trim($args{nick}));
        $nick =~ s/\*/%/g;
        push @where, "(nick LIKE $nick)";
    }

    if ($args{exclude_text}) {
        foreach my $query (@{$args{exclude_text}}) {
            $query = $dbh->quote(trim($query));
            $query =~ s/^'/'%/;
            $query =~ s/'$/%'/;
            push @where, "(NOT (data LIKE $query))";
        }
    }

    if ($args{include_text}) {
        foreach my $query (@{$args{include_text}}) {
            $query = $dbh->quote(trim($query));
            $query =~ s/^'/'%/;
            $query =~ s/'$/%'/;
            push @where, "(data LIKE $query)";
        }
    }

    if ($args{date_after}) {
        push @where, "(time >= " . $args{date_after} . ")";
    }

    if ($args{date_before}) {
        push @where, "(time <= " . $args{date_before} . ")";
    }

    if (!@where) {
        push @where, '(1=1)';
    }
    $sql .= join(" AND ", @where) . " ";

    if ($args{order}) {
        $sql .= "ORDER BY " . $args{order} . " ";
    }

    if ($args{limit}) {
        $sql .= "LIMIT " . $args{limit} . " ";
    } elsif ($args{limit_last}) {
        $sql .= "LIMIT ((SELECT COUNT(1) FROM logs WHERE " . join(" AND ", @where) .
                ") - " . $args{limit_last} .
                ")," . $args{limit_last};
    }

    if ($args{debug_sql}) {
        print STDERR "$sql\n";
    }

    my $sth;
    eval {
        $sth = $dbh->prepare($sql);
        $sth->execute;
    };
    if ($@) {
        die "$@\n\n$sql\n";
    }

    while (my @val = $sth->fetchrow_array) {
        my $event = LogBot::Event->new(
            channel => $self->{channel},
            id   => $val[0],
            time => $val[1],
            nick => $val[2],
            type => $val[3],
            text => $val[4],
        );
        last unless $args{callback}->($event);
    }
}

sub seen {
    my ($self, $nick) = @_;
    my $dbh = $self->{dbh};

    $nick = $dbh->quote(trim($nick));
    $nick =~ s/\*/%/g;

    my $sql = "SELECT rowid,event,time,nick,data FROM logs WHERE " .
              "((event = " . EVENT_PUBLIC . ") OR (event = " . EVENT_ACTION . ")) " .
              "AND (nick LIKE $nick) " .
              "ORDER BY time DESC " .
              "LIMIT 1";

    my $sth = $dbh->prepare($sql);
    if (!defined $sth) {
        return $dbh->errstr;
    }
    $sth->execute;

    while (my($id, $type, $time, $nick, $text) = $sth->fetchrow_array) {
        return LogBot::Event->new(
            id      => $id,
            type    => $type,
            time    => $time,
            channel => $self->{channel},
            nick    => $nick,
            text    => $text,
        );
    }

    return;
}

sub meta {
    my ($self, $name, $event) = @_;
    if (defined($event)) {
        $self->{dbh}->do(
            "INSERT OR REPLACE INTO logs_meta(name, id) VALUES(?, ?)",
            undef,
            $name, $event->{id}
        );
    } else {
        my $sql = "SELECT logs.rowid,logs.event,logs.time,logs.nick,logs.data 
                     FROM logs_meta
                          INNER JOIN logs ON logs.rowid = logs_meta.id
                    WHERE logs_meta.name = ?
                    LIMIT 1";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($name);
        while (my($id, $type, $time, $nick, $text) = $sth->fetchrow_array) {
            return LogBot::Event->new(
                id      => $id,
                type    => $type,
                time    => $time,
                channel => $self->{channel},
                nick    => $nick,
                text    => $text,
            );
        }
        return;
    }
}

sub last_updated {
    my ($self) = @_;
    return gmtime((stat $self->{filename})[9]);
}

sub size {
    my ($self) = @_;
    return -s $self->{filename};
}

sub event_count {
    my ($self) = @_;
    return $self->{dbh}->selectrow_array("
        SELECT COUNT(*) FROM logs
    ");
}

sub _filename {
    my ($self, $channel) = @_;
    $channel =~ s/^#//;
    $channel =~ s/[^a-z1-9_-]/_/g;
    my $path = LogBot->config->{data_path} . '/db';
    mkdir($path) unless -d $path;
    $path .= '/' . $self->{network};
    mkdir($path) unless -d $path;
    return "$path/$channel.db";
}

1;
