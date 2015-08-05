use v5.10;
use strict;
use warnings;

package HTML::Gumbo;

our $VERSION = '0.13';

require XSLoader;
XSLoader::load('HTML::Gumbo', $VERSION);

=head1 NAME

HTML::Gumbo - HTML5 parser based on gumbo C library

=head1 DESCRIPTION

L<Gumbo|https://github.com/google/gumbo-parser> is an implementation
of L<the HTML5 parsing algorithm|http://www.w3.org/TR/html5/syntax.html>
implemented as a pure C99 library with no outside dependencies.

Goals and features of the C library:

=over 4

=item * Fully conformant with the HTML5 spec.

=item * Robust and resilient to bad input.

=item * Simple API that can be easily wrapped by other languages. (This is one of such wrappers.)

=item * Support for source locations and pointers back to the original text.
(Not exposed by this implementation at the moment.)

=item * Relatively lightweight, with no outside dependencies.

=item * Passes all html5lib-0.95 tests.

=item * Tested on over 2.5 billion pages from Google's index.

=back

=head1 SUPPORTED OUTPUT FORMATS

=head2 string

Beta readiness.

HTML is parsed and re-built from the tree, so tags are balanced
(except void elements). Since fragments parsing is not supported
at the moment the result always gets html, head and body elements.

No additional arguments for this format.

    $html = HTML::Gumbo->new->parse( $html );

=head2 callback

Beta readiness.

L<HTML::Parser> like interface. Pass a sub as C<callback> argument to
L</parse> method and it will be called for every node in the document:

    HTML::Gumbo->new->parse( $html, format => 'callback', callback => sub {
        my ($event) = shift;
        if ( $event eq 'document start' ) {
            my ($doctype) = @_;
        }
        elsif ( $event eq 'document end' ) {
        }
        elsif ( $event eq 'start' ) {
            my ($tag, $attrs) = @_;
        }
        elsif ( $event eq 'end' ) {
            my ($tag) = @_;
        }
        elsif ( $event eq /^(text|space|cdata|comment)$/ ) {
            my ($text) = @_;
        }
        else {
            die "Unknown event";
        }
    } );

Note that 'end' events are not generated for
L<void elements|http://www.w3.org/TR/html5/syntax.html#void-elements>,
for example C<hr>, C<br> and C<img>.

No additional arguments except mentioned C<callback>.

=head2 tree

Alpha stage.

Produces tree based on L<HTML::Element>s, like L<HTML::TreeBuilder>.

There is major difference from HTML::TreeBuilder, this method produces
top level element with tag name 'document' which may have doctype, comments
and html tags.

Yes, it's not ready to use as drop in replacement of tree builder. Patches
are wellcome. I don't use this formatter at the moment.

=head1 CHARACTER ENCODING OF THE INPUT

The C parser works only with UTF-8, so you have several options to make
sure input is UTF-8. First of all define C<input_is>:

=over 4

=item string

Input is Perl string, for example obtained from L<HTTP::Response/decoded_content>.
Default value.

=item octets

Input are octets. Partial implementation of
L<encoding sniffing algorithm|http://www.w3.org/TR/html5/syntax.html#encoding-sniffing-algorithm>
is used:

=over 4

=item C<encoding> argument

Use it to hardcode a specific encoding.

=item BOM

UTF-8/UTF-16 BOMs are checked.

=item C<encoding_content_type>

Encdoning from rransport layer, charset in content-type header.

=item Prescan

Not implemented, follow L<issue 58|https://github.com/google/gumbo-parser/issues/58>.

HTML5 defines L<prescan algorithm|http://www.w3.org/TR/html5/syntax.html#prescan-a-byte-stream-to-determine-its-encoding>
that extracts encoding from meta tags in the head.

It would be cool to get it in the C library, but I will accept a patch that impements it in pure perl.

=item C<encoding_tentative> argument

The likely encoding for this page, e.g. based on the encoding of the
page when it was last visited.

=item nested browsing context

Not implemented. Fragment parsing with or without context is not implemented. Parser
also has no origin information, so it wouldn't be implemented.

=item autodetection

Not implemented.

Can be implemented using L<Encode::Detect::Detector>. Patches are welcome.

=item otherwise

It B<dies>.

=back

=item C<utf8>

Use utf8 as input_is when you're sure input is UTF-8, but octets.
No pre-processing at all. Should only be used on trusted input or
when it's preprocessed already.

=back

=head1 METHODS

=head2 new

    my $parser = HTML::Gumbo->new;

No options at the moment.

=head2 parse

    my $res = $parser->parse(
        "<h1>hello world!</h1>",
        format => 'tree',
        input_is => 'string',
    );

Takes html string and pairs of named arguments:

=over 4

=item format

Output format, default is string. See L</SUPPORTED OUTPUT FORMATS>.

=item input_is

Whether html is perl 'string', 'octets' or 'utf8' (octets known to
be utf8). See L</CHARACTER ENCODING OF THE INPUT>.

=item encoding, encoding_content_type, encoding_tentative

See L</CHARACTER ENCODING OF THE INPUT>.

=item ...

Some formatters may have additional arguments.

=back

Return value depends on the picked format.

=cut

sub new {
    my $proto = shift;
    return bless {@_}, ref($proto) || $proto;
}

sub parse {
    my $self = shift;
    my $what = shift;
    my %args = @_;

    my $format = $args{'format'} || 'string';
    my $method = 'parse_to_'. $format;
    die "'$format' format is not supported"
        unless $self->can($method);

    my $input_is = $args{'input_is'} || 'string';
    if ( $input_is eq 'string' ) {
        utf8::encode($what);
    }
    elsif ( $input_is eq 'utf8' ) {
    }
    elsif ( $input_is eq 'octets' ) {
        my $enc = $args{'encoding'};
        unless ( $enc ) {
            if ( $input_is =~ /^(?: (\x{FE}\x{FF}) | (\x{FF}\x{FE}) | \x{EF}\x{BB}\x{BF} )/x ) {
                $enc = $1 ? 'UTF-16BE' : $2 ? 'UTF-16LE' : 'UTF-8';
            }
            elsif ( $enc = $args{'encoding_content_type'} ) {
            }
            elsif ( $enc = $args{'encoding_tentative'} ) {
            }
            else {
                die "Encoding detection is not implemented";
            }

            Encode::from_to($what, $enc, 'UTF-8');
        }
    }
    return $self->$method( \$what, %args );
}

sub parse_to_callback {
    my ($self, $buf, %rest) = @_;
    die "No callback provided" unless $rest{'callback'};
    return $self->_parse_to_callback( $buf, $rest{'callback'} );
}

=head1 AUTHOR

Ruslan Zakirov E<lt>ruz@bestpractical.comE<gt>

=head1 LICENSE

Under the same terms as perl itself.

=cut

1;
