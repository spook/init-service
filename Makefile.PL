use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Init::Service',
    AUTHOR           => q{Uncle Spook <spook@MisfitMountain.org>},
    VERSION_FROM     => 'lib/Init/Service.pm',
    ABSTRACT_FROM    => 'lib/Init/Service.pm',
    LICENSE          => 'MIT',
    EXE_FILES        => ['bin/init-service'],
    PL_FILES         => {},
    MIN_PERL_VERSION => '5.006',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '0',
    },
    BUILD_REQUIRES => {
        'Test::More' => '0',
    },
    PREREQ_PM => {
        #'ABC'              => '1.6',
        #'Foo::Bar::Module' => '5.0401',
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Init-Service-*' },
);
