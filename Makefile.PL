use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'GrowthForecast',
    VERSION_FROM  => 'lib/GrowthForecast.pm',
    PREREQ_PM     => {
        'Kossy' => '0.01',
    },
    MIN_PERL_VERSION => '5.010000',
);

