use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'GrowthForecast',
    VERSION_FROM  => 'lib/GrowthForecast.pm',
    PREREQ_PM     => {
        'Kossy' => '0.01',
        'DBIx::Sunny' =>  '0.14',
        'DBD::SQLite' => '1.33',
        'Time::Piece' => '1.15',
        'HTTP::Date' => 0,
        'File::Zglob' => '0.09',
        'Log::Minimal' => '0.09',
        'Starlet' => '0.14',
        'Parallel::Scoreboard' => '0.03',
        'Plack::Builder::Conditionals' => '0.03',
    },
    MIN_PERL_VERSION => '5.008001',
);

