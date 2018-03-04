package LogBot::MemCache;
use local::lib;
use v5.10;
use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/lib";

use Cache::Memcached::Fast ();
use IO::Socket::INET ();

sub new {
    my ($class) = @_;

    my $server = $ENV{LOGBOT_MEMCACHE} // '';

    if ($server =~ /^([^:]+):(\d+)$/) {
        my ($host, $port) = ($1, $2);
        if (!IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => 'tcp', Timeout => 1)) {
            warn "failed to connect to memcached on $server\n";
            undef $server;
        }
    } else {
        undef $server;
    }
    if (!$server) {
        return LogBot::MemCache::None->new();
    }

    return bless(
        {
            cache => Cache::Memcached::Fast->new({ servers => [{ address => $server }], nowait => 1 }),
        },
        $class
    );
}

sub get {
    my ($self, $key, $callback) = @_;
    my $cache = $self->{cache};

    my $cached = $cache->get($key);
    return $cached if defined $cached;

    my $value = $callback->();
    $cache->set($key, $value);
    return $value;
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

sub get {
    my (undef, undef, $callback) = @_;
    return $callback->();
}

1;
