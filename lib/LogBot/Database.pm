package LogBot::Database;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use DBD::SQLite::Constants qw( :file_open );
use DBI ();
use LogBot::Util qw( file_for squash_error timestamp );
use Time::HiRes qw( sleep );
use Try::Tiny qw( catch finally try );

our @EXPORT_OK = qw(
    dbh dbh_disconnect
    execute_with_timeout
    execute_with_retry
    replace_sql_placeholders
    like_value
);
use parent 'Exporter';

my $cache_ro = {};
my $cache_rw = {};

sub dbh {
    my ($config, %params) = @_;

    if ($params{cached}) {
        return $params{read_write}
            ? ($cache_rw->{ $config->{name} } //= _dbh_read_write($config))
            : ($cache_ro->{ $config->{name} } //= _dbh_read_only($config));
    } else {
        return $params{read_write}
            ? _dbh_read_write($config)
            : _dbh_read_only($config);
    }
}

sub _dbh_read_write {
    my ($config) = @_;

    # connect
    my $dbh = DBI->connect(
        'DBI:SQLite:' . file_for($config, 'store'),
        '', '', {
            PrintError                       => 0,
            RaiseError                       => 1,
            sqlite_use_immediate_transaction => 1,
        }
    );

    # schema check
    my $schema_version = $dbh->selectrow_array('PRAGMA user_version');
    die 'schema from the future' if $schema_version > 1;
    $dbh->do('PRAGMA user_version=1') if $schema_version != 1;

    # initialise db
    _do_multi(
        $dbh,
        'CREATE TABLE IF NOT EXISTS logs(id INTEGER PRIMARY KEY, old_id INTEGER, time REAL, channel TEXT, nick TEXT, type INTEGER, text TEXT)',
        'CREATE TABLE IF NOT EXISTS topics(id INTEGER PRIMARY KEY, time REAL, channel TEXT, topic TEXT)',
        'CREATE INDEX IF NOT EXISTS idx_time ON logs(time)',
        'CREATE INDEX IF NOT EXISTS idx_channel ON logs(channel)',
        'CREATE INDEX IF NOT EXISTS idx_nick ON logs(nick COLLATE NOCASE)',
        'CREATE INDEX IF NOT EXISTS idx_text ON logs(text)',
        'CREATE INDEX IF NOT EXISTS idx_channel_time ON logs(channel, time)',
        'CREATE INDEX IF NOT EXISTS idx_topic ON topics(channel)',
    );

    # initalise fts
    _do_multi(
        $dbh,
        'CREATE VIRTUAL TABLE IF NOT EXISTS logs_fts USING fts5(text, time UNINDEXED, content=logs, content_rowid=id)',
        'CREATE TRIGGER IF NOT EXISTS logs_ai AFTER INSERT ON logs BEGIN
            INSERT INTO logs_fts(rowid, text) VALUES (new.id, new.text);
        END',
        'CREATE TRIGGER IF NOT EXISTS logs_ad AFTER DELETE ON logs BEGIN
            INSERT INTO logs_fts(logs_fts, rowid, text) VALUES("delete", old.id, old.text);
        END',
        'CREATE TRIGGER IF NOT EXISTS logs_au AFTER UPDATE ON logs BEGIN
            INSERT INTO logs_fts(logs_fts, rowid, text) VALUES("delete", old.id, old.text);
            INSERT INTO logs_fts(rowid, text) VALUES (new.id, new.text);
        END;',
    );

    # use write-ahead log jounaling
    $dbh->do('PRAGMA journal_mode=WAL');

    # sync at critical moments but less frequently than default
    $dbh->do('PRAGMA synchronous=NORMAL');

    return $dbh;
}

sub _dbh_read_only {
    my ($config) = @_;

    # init
    my $file = file_for($config, 'store');
    _dbh_read_write($config) if !-e $file;

    # connect
    my $dbh = DBI->connect(
        'DBI:SQLite:' . $file,
        '', '', {
            PrintError        => 0,
            RaiseError        => 1,
            sqlite_open_flags => SQLITE_OPEN_READONLY,
        }
    );

    # schema check
    die 'schema from the future' if $dbh->selectrow_array('PRAGMA user_version') > 1;

    return $dbh;
}

sub dbh_disconnect {
    my ($config) = @_;
    delete $cache_rw->{ $config->{name} };
    delete $cache_ro->{ $config->{name} };
}

sub _do_multi {
    my ($dbh, @statements) = @_;
    foreach my $statement (@statements) {
        $dbh->do($statement);
    }
}

sub execute_with_timeout {
    my ($dbh, $sql, $values, $timeout) = @_;

    my $rows;
    my $timed_out  = 0;
    my $start_time = time();

    $dbh->sqlite_progress_handler(5_000, sub { return time() - $start_time > $timeout });

    try {
        $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, @{$values});
    }
    catch {
        if (/selectall_arrayref failed: interrupted/) {
            $timed_out = 1;
        } else {
            die $_;
        }
    }
    finally {
        $dbh->sqlite_progress_handler(0, undef);
    };

    return $timed_out ? undef : $rows;
}

sub execute_with_retry {
    my ($config, $callback, $attempts) = @_;

    $attempts //= 20;
    my $result = 0;
    while ($attempts && !$result) {
        try {
            my $dbh = dbh($config, read_write => 1, cached => 1);
            $result = $callback->($dbh);
        }
        catch {
            say timestamp(), ' !! ', squash_error($_);
            dbh_disconnect($config);
            sleep(0.5);
        };

        $attempts--;
    }
    return $result;
}

sub replace_sql_placeholders {
    my ($dbh, $sql, $values) = @_;

    foreach my $param (@{$values}) {
        $sql =~ s/\?/$dbh->quote($param)/e;
    }

    return $sql;
}

sub like_value {
    my ($field, $value) = @_;
    my $condition = $field . ' LIKE ?';
    if ($value =~ s/(?=[\\%_])/\\/g) {
        $condition .= ' ESCAPE \'\\\'';
    }
    return ($condition, '%' . $value . '%');
}

1;
