requires 'Alien::RRDtool', '0.05';
requires 'Kossy',          '0.27';
requires 'DBIx::Sunny',    '0.14';
requires 'DBD::SQLite',    '1.33';
requires 'Time::Piece',    '1.15';
requires 'HTTP::Date';
requires 'File::Zglob',    '0.09';
requires 'Log::Minimal',   '0.16';
requires 'List::MoreUtils';
requires 'Starlet',        '0.20';
requires 'HTTP::Parser::XS', '0.16';
requires "URL::Encode::XS";
requires 'Proclet',        '0.31';
requires 'Plack::Builder::Conditionals',        '0.03';
requires 'Scope::Container',                    '0.04';
requires 'Plack::Middleware::Scope::Container', '0.04';
requires 'Plack::Middleware::AxsLog',           '0.13';
requires 'Scope::Container::DBI',               '0.09';
requires 'JSON', 2;
requires "JSON::XS";
requires 'Class::Accessor::Lite';

on 'test' => sub {
    requires 'Test::More',     '0.96';
    requires 'Test::Requires', '0.06';
};


