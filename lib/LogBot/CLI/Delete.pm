package LogBot::CLI::Delete;
use local::lib;
use v5.10;
use strict;
use warnings;

use LogBot::Database qw( dbh execute_with_retry like_value replace_sql_placeholders );
use LogBot::Util qw( event_to_string plural touch );
use Mojo::Util qw( trim );
use Term::ReadKey qw( ReadKey ReadMode );
use Text::ParseWords qw( quotewords );
use Try::Tiny qw( finally try );

END {
    ReadMode(0);
}

sub manifest {
    return {
        command => 'delete',
        usage   => 'delete',
        help    => 'delete events',
    };
}

sub execute {
    my ($self, $configs, @args) = @_;

    my $query = join(' ', @args);
    my $nick = '';
    if ($query =~ s/^<([^>]+)>\s*//) {
        $nick = $1;
    }
    $query = trim($query);
    $nick  = trim($nick);

    foreach my $config (@{$configs}) {
        my $dbh = dbh($config, read_write => 1);

        my (@where, @values);
        if ($query) {
            my @parts;
            foreach my $word (quotewords('\s+', 0, $query)) {
                my ($condition, $value) = like_value(text => $word);
                push @parts,  $condition;
                push @values, $value;
            }
            if (!@parts) {
                my ($condition, $value) = like_value(text => $query);
                push @parts,  $condition;
                push @values, $value;
            }
            push @where, join(' AND ', @parts);
        }
        if ($nick) {
            push @where,  'nick = ?';
            push @values, $nick;
        }
        die "query not provided\n" unless @where;

        my $sql_filter = 'FROM logs WHERE (' . join(') AND (', @where) . ') ORDER BY channel,time';
        my $sql_select = "SELECT * $sql_filter";
        my $sql_count  = "SELECT COUNT(*) $sql_filter";
        say replace_sql_placeholders($dbh, $sql_select, \@values);

        my ($count) = $dbh->selectrow_array($sql_count, undef, @values);
        say 'found ', plural($count, 'match', 'es');
        exit unless $count;

        my $dirty = 0;
        try {
            my $all_y = my $all_n = 0;
            my $sth = $dbh->prepare($sql_select);
            $sth->execute(@values);
            while (my $event = $sth->fetchrow_hashref) {
                say event_to_string($event);

                my $key;
                if ($all_y) {
                    $key = 'y';
                } elsif ($all_n) {
                    $key = 'n';
                } else {
                    print '(y)es (n)o (Y)es to all (N)o to all (q)uit ? ';
                    $key = confirm();
                }

                if ($key eq 'Y') {
                    $all_y = 1;
                    $key   = 'y';
                } elsif ($key eq 'N') {
                    $all_n = 1;
                    $key   = 'n';
                }

                if ($key eq 'y') {
                    execute_with_retry(
                        $config,
                        sub {
                            my ($_dbh) = @_;
                            $_dbh->do('DELETE FROM logs WHERE id = ?', undef, $event->{id});
                            return 1;
                        }
                    ) // die;
                    say 'deleted';
                    $dirty = 1;
                } elsif ($key eq 'n') {
                    print "\r\e[K";
                } else {
                    say '';
                    exit;
                }
            }
        }
        finally {
            touch($config->{_derived}->{file}) if $dirty;
        };
    }

}

sub confirm {
    my $key = '';
    ReadMode(4);
    do {
        $key = ReadKey();
        if (ord($key) == 3 || ord($key) == 27) {
            say '^C';
            ReadMode(0);
            exit;
        }
    } until $key =~ /^[ynYNq]$/;
    ReadMode(0);
    return $key;
}

1;
