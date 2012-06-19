use  ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'GrowthForecast',
    VERSION_FROM  => 'lib/GrowthForecast.pm',
    PREREQ_PM     => {
        'Kossy' => '0.10',
        'DBIx::Sunny' =>  '0.14',
        'DBD::SQLite' => '1.33',
        'Time::Piece' => '1.15',
        'HTTP::Date' => 0,
        'File::Zglob' => '0.09',
        'Log::Minimal' => '0.09',
        'List::MoreUtils' => '0',
        'Starlet' => '0.14',
        'Proclet' => '0.05',
        'Plack::Builder::Conditionals' => '0.03',
        'Scope::Container' => '0.04',
        'Plack::Middleware::Scope::Container' => '0.02',
        'Scope::Container::DBI' => '0.05'
    },
    MIN_PERL_VERSION => '5.008001',
);

