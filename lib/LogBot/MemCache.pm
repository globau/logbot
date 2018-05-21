package LogBot::MemCache;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use Encode qw( decode encode );
use IO::Socket::INET ();
use Memcached::libmemcached qw( /^memcached/ MEMCACHED_BEHAVIOR_BINARY_PROTOCOL );

sub new {
    my ($class, %params) = @_;

    my $server = $ENV{LOGBOT_MEMCACHE} // 'localhost:11211';

    my ($host, $port);
    if ($server =~ /^([^:]+):(\d+)$/) {
        ($host, $port) = ($1, $2);
    } else {
        ($host, $port) = ($server, 11211);  ## no critic (ValuesAndExpressions::RequireNumberSeparators)
    }

    if (IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => 'tcp', Timeout => 1)) {
        my $cache = memcached_create();
        memcached_behavior_set($cache, MEMCACHED_BEHAVIOR_BINARY_PROTOCOL, 1) if $params{binary};
        memcached_server_add($cache, $host, $port);
        return bless({ cache => $cache }, $class);
    }

    warn "failed to connect to memcache on $host:$port\n";
    return LogBot::MemCache::None->new();
}

sub cached {
    my ($self, $key, $callback) = @_;
    my $cache = $self->{cache};

    my $cached = memcached_get($cache, $key);
    return decode('UTF-8', $cached) if defined $cached;

    my $value = scalar($callback->());
    memcached_set($cache, $key, encode('UTF-8', $value));
    return $value;
}

sub get {
    my ($self, $key) = @_;
    my $cache = $self->{cache};
    my $cached = memcached_get($cache, $key);
    return defined $cached ? decode('UTF-8', $cached) : undef;
}

sub set {
    my ($self, $key, $value) = @_;
    my $cache = $self->{cache};
    memcached_set($cache, $key, encode('UTF-8', $value));
}

1;

package LogBot::MemCache::None;
use local::lib;
use v5.10;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless({}, $class);
}

sub cached {
    my (undef, undef, $callback) = @_;
    return $callback->();
}

sub get {
    return undef;
}

sub set {
}

1;
