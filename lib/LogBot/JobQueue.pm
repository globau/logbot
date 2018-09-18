package LogBot::JobQueue;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use Cpanel::JSON::XS qw( decode_json encode_json );
use File::Basename qw( basename );
use LogBot::Util qw( path_for slurp spurt timestamp );
use Time::HiRes qw( time );

sub new {
    my ($class, $config) = @_;
    return bless({ config => $config }, $class);
}

sub publish_job {
    my ($self, $data) = @_;
    my $file;
    do {
        $file = path_for($self->{config}, 'queue') . '/' . $$ . '.' . time() . '.json';
    } while (-e $file);
    spurt($file, encode_json($data));
}

sub fetch_job {
    my ($self) = @_;
    my $spec = path_for($self->{config}, 'queue') . '/*.json';
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
    my ($self, $job) = @_;
    unlink(path_for($self->{config}, 'queue') . '/' . $job)
        || say timestamp(), ' !! ', "failed to delete $job: $!";
}

1;
