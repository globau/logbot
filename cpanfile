# cpanm --verbose --local-lib ~/perl5/ --notest --installdeps .
requires 'DBD::SQLite', '1.54';
requires 'DBI', '1.636';
requires 'Date::Parse', '2.30';
requires 'DateTime', '1.43';
requires 'Digest::xxHash', '2.03';
requires 'EV', '4.22';
requires 'IO::Socket::SSL', '2.049';
requires 'IO::Socket::Socks', '0.74';
requires 'IO::Socket::Timeout', '0.32';
requires 'JSON', '2.94';
requires 'JSON::XS', '3.03';
requires 'List::MoreUtils', '0.419';
requires 'List::Util', '1.33';
requires 'Memcached::libmemcached', '1.001801';
requires 'Mojolicious', '7.65';
requires 'Mojolicious::Plugin::AccessLog', '0.010';
requires 'Net::DNS::Native', '0.15';
requires 'Readonly', '2.05';
requires 'Term::ReadKey', '2.37';
requires 'Time::Duration', '1.20';
requires 'Try::Tiny', '0.28';
requires 'URI::Find', '20160806';
requires 'YAML::Tiny', '1.70';

# cpanm --verbose --local-lib ~/perl5/ --notest --installdeps . --with-develop
on 'develop' => sub {
    requires 'Perl::Tidy', '20170521';
    requires 'Perl::Critic';
};
