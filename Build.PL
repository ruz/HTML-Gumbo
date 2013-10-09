use Module::Build;
use Alien::LibGumbo;

my $alien = Alien::LibGumbo->new;
my $builder = Module::Build->new(
    module_name => 'HTML::Gumbo',

    configure_requires => {
        'Alien::LibGumbo' => 0,
    },
    build_requires => {
        'ExtUtils::CBuilder' => 0,
    },
    requires => {
        'Alien::LibGumbo' => 0,
    },

    extra_compiler_flags => $alien->cflags(),
    extra_linker_flags   => $alien->libs(),
);
$builder->create_build_script;