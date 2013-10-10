use strict;
use warnings;
use Test::More;

use_ok('HTML::Gumbo');

my $parser = HTML::Gumbo->new;
my $res = $parser->parse(<<'END', format => 'gumbo');
<!DOCTYPE html>
<!--This is a comment-->
<h1>hello world!</h1>
END

use Data::Dumper;
diag Dumper $res->document;

is $res->document->type, 'document', 'correct node type';

done_testing();

