requires 'Alien::RRDtool', '0.03';
requires 'Kossy',          '0.10';
requires 'DBIx::Sunny',    '0.14';
requires 'DBD::SQLite',    '1.33';
requires 'Time::Piece',    '1.15';
requires 'HTTP::Date';
requires 'File::Zglob',    '0.09';
requires 'Log::Minimal',   '0.09';
requires 'List::MoreUtils';
requires 'Starlet',        '0.14';
requires 'Proclet',        '0.05';
requires 'Plack::Builder::Conditionals',        '0.03';
requires 'Scope::Container',                    '0.04';
requires 'Plack::Middleware::Scope::Container', '0.02';
requires 'Scope::Container::DBI',               '0.05';

on 'test' => sub {
    requires 'Test::More',     '0.96';
    requires 'Test::Requires', '0.06';
};


