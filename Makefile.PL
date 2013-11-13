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
public/js/bootstrap-alert.js
public/js/bootstrap-modal.js
public/js/html5jp/cpick.js
public/js/jquery-1.10.2.min.js
!;

for my $file ( @files ) {
    install_sharefile $file;
}
auto_set_repository;
WriteAll;

