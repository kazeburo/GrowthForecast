use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'GrowthForecast',
    VERSION_FROM  => 'lib/GrowthForecast.pm',
    PREREQ_PM     => {
        'Kossy' => '0.01',
        'DBIx::Sunny' =>  '0.14',
        'Time::Piece' => '1.15',
        'HTTP::Date' => 0,
        'File::Zglob' => '0.09',
        'Log::Minimal' => '0.09',
    },
    MIN_PERL_VERSION => '5.010000',
);

