package LogBot::JobQueue;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use File::Basename qw( basename );
use JSON::XS qw( decode_json encode_json );
use LogBot::Util qw( path_for slurp spurt timestamp );
use Time::HiRes qw( time );

our @EXPORT_OK = qw(
    publish_job fetch_job delete_job
);
use parent 'Exporter';

sub publish_job {
    my ($config, $data) = @_;
    my $file;
    do {
        $file = path_for($config, 'queue') . '/' . $$ . '.' . time() . '.json';
    } while (-e $file);
    spurt($file, encode_json($data));
}

sub fetch_job {
    my ($config) = @_;
    my $spec = path_for($config, 'queue') . '/*.json';
    my $quit = 0;
    local $SIG{INT} = sub { $quit = 1 };
    while (!$quit) {
        if (my @files = glob($spec)) {
            my $file = shift @files;
            return (basename($file), decode_json(slurp($file)));
        }
        sleep(1);
    }
    return undef;
}

sub delete_job {
    my ($config, $job) = @_;
    unlink(path_for($config, 'queue') . '/' . $job)
        || say timestamp(), ' !! ', "failed to delete $job: $!";
}

1;
