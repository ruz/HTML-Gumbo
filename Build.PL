use Module::Build;
use Alien::LibGumbo;
use ExtUtils::Depends;

my $pkg = ExtUtils::Depends->new('HTML::Gumbo', 'XS::Object::Magic');
my %extra = $pkg->get_makefile_vars;

my $alien = Alien::LibGumbo->new;
my $builder = Module::Build->new(
    module_name => 'HTML::Gumbo',

    configure_requires => {
        'Alien::LibGumbo' => 0,
        'XS::Object::Magic' => 0,
    },
    build_requires => {
        'ExtUtils::CBuilder' => 0,
        'Alien::LibGumbo' => 0,
        'XS::Object::Magic' => 0,
    },
    requires => {
        'Alien::LibGumbo' => 0,
        'XS::Object::Magic' => 0,
    },

    meta_merge => {
        resources => {
            repository => 'https://github.com/ruz/HTML-Gumbo'
        }
    },

    extra_compiler_flags => join( ' ', $alien->cflags(), $extra{'INC'} ),
    extra_linker_flags   => join( ' ', $alien->libs(), $extra{'LIBS'} ),
);
$builder->create_build_script;
