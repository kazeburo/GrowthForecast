#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../extlib/lib/perl5";
use lib "$FindBin::Bin/../lib";
use File::Basename;
use Getopt::Long;
use GrowthForecast;
use GrowthForecast::RRD;
use File::ShareDir qw/dist_dir/;
use Cwd;
use File::Path qw/mkpath/;
use Log::Minimal;
use Pod::Usage;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'data-dir=s' => \my $data_dir,
    "h|help" => \my $help,
);

if ( $help ) {
    pod2usage(-verbose=>2,-exitval=>0);
}

my $root_dir = "$FindBin::Bin/..";
if ( ! -f "$root_dir/lib/GrowthForecast.pm" ) {
    $root_dir = dist_dir('GrowthForecast');
}
if ( !$data_dir ) {
    $data_dir = $root_dir . '/data';
}
else {
    $data_dir = Cwd::realpath($data_dir);
}

my $rrd = GrowthForecast::RRD->new(
    data_dir => $data_dir,
    root_dir => $root_dir,
);

my $data = {};
$data->{mode} = 'GAUGE';
$data->{md5}  = 'test';
$data->{number} = 1;
$data->{subtract} = 0;
$rrd->path($data); # create
$rrd->update($data);

__END__

=head1 NAME

benchmark_rrd.pl - benchmark rrd

=head1 SYNOPSIS

$ benchmark_rrd.pl

=head1 DESCRIPTION

    Benchmark RRD

=head1 OPTIONS

=over 3

=item --data-dir

 A directory where sqlite file is stored. Default is `data`.

=item -h --help

 Display help

=back

AUTHOR
    Naotoshi Seo <sonots {at} gmail.com>

LICENSE
    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

