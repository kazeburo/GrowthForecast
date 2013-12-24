# requires Module::Install
# requires Module::Install::ReadmeFromPod
# requires Module::Install::Repository
# requires Module::Install::ShareFile
# requires Module::Install::CPANfile

use inc::Module::Install;
name 'GrowthForecast';
all_from 'lib/GrowthForecast.pm';
perl_version '5.008001';
readme_from 'growthforecast.pl';
cpanfile;

tests 't/*.t t/*/*.t';
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
public/favicon.ico
public/fonts/glyphicons-halflings-regular.eot
public/fonts/glyphicons-halflings-regular.svg
public/fonts/glyphicons-halflings-regular.ttf
public/fonts/glyphicons-halflings-regular.woff
public/js/bootstrap.min.js
public/js/jquery-1.10.2.min.js
public/js/jquery.storageapi.min.js
public/js/site.js
!;

for my $file ( @files ) {
    install_sharefile $file;
}
auto_set_repository;
WriteAll;

