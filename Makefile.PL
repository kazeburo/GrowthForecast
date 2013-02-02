use inc::Module::Install;
name 'GrowthForecast';
all_from 'lib/GrowthForecast.pm';
perl_version '5.008001';
readme_from 'growthforecast.pl';

requires 'Alien::RRDtool' => '0.03';
requires 'Kossy' => '0.10';
requires 'DBIx::Sunny' =>  '0.14';
requires 'DBD::SQLite' => '1.33';
requires 'Time::Piece' => '1.15';
requires 'HTTP::Date';
requires 'File::Zglob' => '0.09';
requires 'Log::Minimal' => '0.09';
requires 'List::MoreUtils';
requires 'Starlet' => '0.14';
requires 'Proclet' => '0.05';
requires 'Plack::Builder::Conditionals' => '0.03';
requires 'Scope::Container' => '0.04';
requires 'Plack::Middleware::Scope::Container' => '0.02';
requires 'Scope::Container::DBI' => '0.05';

tests 't/*.t t/*/*.t';
test_requires 'Test::More';
test_requires  'Test::Requires';
install_script 'growthforecast.pl';

my @files = qw!
views/add_complex.tx
views/base.tx
views/docs.tx
views/edit.tx
views/edit_complex.tx
views/index.tx
views/list.tx
views/view.tx
views/view_graph.tx
public/css/bootstrap.min.css
public/js/bootstrap-alerts.js
public/js/bootstrap-modal.js
public/js/html5jp/cpick.js
public/js/jquery-1.5.2.min.js
!;

for my $file ( @files ) {
    install_sharefile $file;
}
auto_set_repository;
WriteAll;

