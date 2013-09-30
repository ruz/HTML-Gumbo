use strict;
use warnings;
use utf8;
use Test::More;

use_ok('HTML::Gumbo');

my $parser = HTML::Gumbo->new;
my $input = <<'END';
<!DOCTYPE html>
<!--This is a comment-->
<h1>hello world!</h1>
<div class="test">
  <p>first para
  <p>second
</div>
<div>
  <img />
  <img alt="&copy;">
  <img></img>
</div>
<some>
END
my $expected = <<'END';
<!DOCTYPE html>
<!--This is a comment--><html><head></head><body><h1>hello world!</h1>
<div class="test">
  <p>first para
  </p><p>second
</p></div>
<div>
  <img>
  <img alt="©">
  <img>
</div>
<some>
</some></body></html>
END
my $res = $parser->parse($input);
is $res, $expected, 'very basic test';

$input = <<'END';
<div class="&quot;&bull;&amp;bull;&">&lt;p&gt;</div>
END
$expected = <<'END';
<html><head></head><body><div class="&quot;•&amp;bull;&amp;">&lt;p&gt;</div>
</body></html>
END
$res = $parser->parse($input);
is $res, $expected, 'very basic test';

$input = <<'END';
<pre>foo</pre>
<pre>
foo</pre>
<pre>

foo</pre>
END
$expected = <<'END';
<html><head></head><body><pre>
foo</pre>
<pre>
foo</pre>
<pre>

foo</pre>
</body></html>
END
$res = $parser->parse($input);
is $res, $expected, 'very basic test';



done_testing();
