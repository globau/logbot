package LogBot::IRC;

use strict;
use warnings;

use Class::Sniff;
use IRC::Utils ':ALL';
use LogBot;
use LogBot::Bot;
use LogBot::Constants;
use POE;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotAddressed;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::NickServID;
use Scalar::Util 'blessed';

sub start {
    my ($class) = @_;

    LogBot->connect();
    $poe_kernel->run();
}

sub connect_network {
    my ($class, $network) = @_;

    return unless grep { $_->{join} } $network->channels;
    printf STDERR "Connecting to %s (%s:%s)\n", $network->{network}, $network->{server}, $network->{port};

    my $irc = POE::Component::IRC->spawn(
        nick        => $network->{nick},
        ircname     => $network->{name},
        server      => $network->{server},
        port        => $network->{port},
        debug       => 1,
    ) or die "failed: $!\n";

    if ($network->{password}) {
        $irc->plugin_add(
            'NickServID',
            POE::Component::IRC::Plugin::NickServID->new(
                Password => $network->{password}
            )
        );
    }

    $irc->plugin_add(
        'BotAddressed',
        POE::Component::IRC::Plugin::BotAddressed->new()
    );

    my $bot = LogBot::Bot->new($irc, $network);

    my @poe_methods = Class::Sniff->new({ class => $class })->methods;
    @poe_methods = grep { /^irc_/ } @poe_methods;
    push @poe_methods, '_start';

    my @bot_methods = Class::Sniff->new({ class => blessed($bot) })->methods;
    @bot_methods = grep { /^irc_/ } @bot_methods;

    POE::Session->create(
        package_states => [ $class => \@poe_methods ],
        object_states => [ $bot => \@bot_methods ],
        heap => { irc => $irc, bot => $bot, network => $network },
        options => { trace => LogBot->config->{bot}->{debug_poe}, default => 0 },
    );

    $network->{bot} = $bot;
}

sub _start {
    my $heap = $_[HEAP];
    my $irc = $heap->{irc};

    $irc->yield(register => 'all');
    $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
    $irc->plugin_add( 'Connector' => $heap->{connector} );
    $irc->yield(connect => {});
    return;
}

sub irc_001 {
    my $sender = $_[SENDER];
    my $heap = $_[HEAP];
    my $irc = $heap->{irc};
    my $bot = $heap->{bot};
    my $network = $heap->{network};

    print STDERR "Connected to ", $irc->server_name(), "\n";
    foreach my $channel ($network->channels) {
        $bot->join($channel);
    }
    return;
}

sub irc_join {
    my ($sender, $kernel, $heap) = @_[SENDER, KERNEL, HEAP];
    my $irc = $heap->{irc};
    my $bot = $heap->{bot};
    my $nick = parse_user($_[ARG0]);
    my $channel = $_[ARG1];

    $bot->joined($channel, $nick);
}

sub irc_part {
    my ($sender, $kernel, $heap) = @_[SENDER, KERNEL, HEAP];
    my $irc = $heap->{irc};
    my $bot = $heap->{bot};
    my $nick = parse_user($_[ARG0]);
    my $channel = $_[ARG1];
    my $what = $_[ARG2];

    $bot->parted($channel, $nick, $what);
}

sub irc_quit {
    my ($sender, $kernel, $heap) = @_[SENDER, KERNEL, HEAP];
    my $irc = $heap->{irc};
    my $bot = $heap->{bot};
    my $nick = parse_user($_[ARG0]);
    my $what = $_[ARG1];

    $bot->quit($nick, $what);
}

sub irc_msg {
    my $bot = $_[HEAP]->{bot};
    my $nick = parse_user($_[ARG0]);
    my $what = $_[ARG2];

    $bot->command($nick, $nick, $what);
    return;
}

sub irc_public {
    my $bot = $_[HEAP]->{bot};
    my $nick = parse_user($_[ARG0]);
    my $channel = $_[ARG1]->[0];
    my $what = $_[ARG2];

    $bot->public($channel, $nick, $what);
    return;
}

sub irc_ctcp_action {
    my $bot = $_[HEAP]->{bot};
    my $nick = parse_user($_[ARG0]);
    my $channel = $_[ARG1]->[0];
    my $what = $_[ARG2];

    $bot->action($channel, $nick, $what);
    return;
}

sub irc_bot_addressed {
    my $bot = $_[HEAP]->{bot};
    my $nick = parse_user($_[ARG0]);
    my $channel = $_[ARG1]->[0];
    my $what = $_[ARG2];

    $bot->command($channel, $nick, $what);
    return;
}

1;

