package LogBot::Command::Bug;
use LogBot::BP;

use HTML::Entities qw(decode_entities);
use LWP::UserAgent;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->{bot} = shift;
    return $self;
}

sub execute {
    my ($self, $network, $channel, $nick, $command) = @_;
    return unless $command =~ /^bug\s+(\d+)/i;
    $self->{bot}->respond($channel, $nick, $self->_summary($1));
    return 1;
}

sub _summary {
    my ($self, $id) = @_;

    my $response = $self->_get($id);

    if (!$response->is_success) {
        return sprintf "Failed to get bug %s: %s", $id, $response->status_line;
    }

    my $xml = $response->content;
    if ($xml !~ /\<bugzilla /) {
        return sprintf "Failed to get bug %s", $id;
    }

    # check for http error

    if ($xml =~ m#<H1>An Error Occurred</H1>#) {
        my ($error) = $xml =~ /\n\d+ ([^\n]+)/;
        return sprintf "Error fetching bug %s: %s", $id, $error;
    }

    # Bug https://bugzil.la/258711 min, --, Bugzilla 2.18, wurblzap, ASSI, move.pl should honour emailsuffix

    # min               //bug/bug_severity (first 3 chars)
    # --                //bug/priority
    # Bugzilla 2.18     //bug/target_milestone
    # wurblzap          //bug/assigned_to (up to @)
    # ASSI              //bug/bug_status (first 4 chars)
    # move.pl...        //bug/short_desc

    # check for bugzilla error

    if ($xml =~ /<bug error="([^"]+)">/) {
        my $error = decode_entities($1);
        return sprintf "Bug %s was not found.", $id if $error eq 'NotFound';
        return sprintf "Bug https://bugzil.la/%s is not accessible", $id if $error eq 'NotPermitted';
        return sprintf "Bug %s was not found.", $id if $error eq 'NotFound';
        return sprintf "Invalid Bug ID %s", $id if $error eq 'InvalidBugId';
        return "BMO returned an error for bug %s: %s", $id, $error;
    }

    my %bug;
    foreach my $field (qw(bug_severity priority target_milestone assigned_to bug_status resolution short_desc bug_id)) {
        ($bug{$field}) = $xml =~ /<$field[^>]*>([^<]+)/;
        $bug{$field} = decode_entities($bug{$field} || '');
    }

    return sprintf
        "Bug https://bugzil.la/%s %s, %s, %s, %s, %s %s, %s",
        $bug{bug_id},
        $bug{bug_severity},
        $bug{priority},
        $bug{target_milestone},
        $bug{assigned_to},
        $bug{bug_status},
        $bug{resolution},
        $bug{short_desc}
    ;

}

sub _get {
    my ($self, $id) = @_;

    if (!$self->{ua}) {
        $self->{ua} = LWP::UserAgent->new();
        $self->{ua}->agent('logbot');
    }

    return $self->{ua}->get(
        "https://bugzilla.mozilla.org/show_bug.cgi?ctype=xml&excludefield=long_desc&excludefield=attachment&id=$id"
    );
}

1;
