package LogBot::Template;
use LogBot::BP;

use Mojo::Template;
use File::Slurp;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $SIG{__DIE__} = sub {
        my $message = shift;
        eval '
            use LogBot::CGI;
            print LogBot::CGI->instance->header();
            $self->render("error.html", message => $message);
        ';
        if ($@) {
            print "content-type: text/plain\n\n$message";
        }
        exit;
    };
    $self->{cache} = {};
    return $self;
}

sub render {
    my ($self, $file, %args) = @_;
    my $cache = $self->{cache};

    my @arg_names = sort keys %args;
    my $key = join('|', ($file, @arg_names));
    my $mt = $cache->{$key};

    my @arg_values;
    foreach my $name (@arg_names) {
        push @arg_values, $args{$name};
    }

    if ($mt) {
        print $mt->interpret(@arg_values);
        return;
    }

    $mt = Mojo::Template->new();
    $mt->auto_escape(1);

    my $prepend =
        'use LogBot::Constants;' .
        'my $cgi=LogBot::CGI->instance;';
    foreach my $name (@arg_names) {
        $prepend .= 'my $' . $name . ' = shift;';
    }
    $mt->prepend($prepend);

    print $mt->render_file("tmpl/$file.ep", @arg_values);

    $cache->{$key} = $mt;
}

1;
