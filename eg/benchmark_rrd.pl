#!/usr/bin/perl

use strict;
use warnings;
use utf8;
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
use Time::HiRes;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use Encode;

my $from = 1;
my $number = 1;
my $repeat = 1;
my $parallel = 1;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'data-dir=s'   => \my $data_dir,
    'f|from=i'     => \$from,
    'n|number=i'   => \$number,
    'r|repeat=i'   => \$repeat,
    'p|parallel=i' => \$parallel, # @todo
    'c|create'     => \my $create,
    's|short'      => \my $short,
    'm|md5'        => \my $md5,
    'd|daemon=s'   => \my $rrdcached,
    "h|help"       => \my $help,
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
    rrdcached => $rrdcached,
);

my $md5_func;
if ( $md5 ) {
    $md5_func = sub { md5_hex(Encode::encode_utf8(shift)) }
}
else {
    $md5_func = sub { shift }
}

sub bench(&) {
    my $code = shift;
    my $data = {};
    $data->{mode} = 'GAUGE';

    for (my $r = 0; $r < $repeat; $r++) {
        my $start_time = Time::HiRes::time;
        for (my $n = $from; $n < $from + $number; $n++) {
            $data->{md5}    = $md5_func->($n);
            $data->{number} = int(rand($number));
            $code->($data);
        }
        printf("%0.3f to %s %d %sgraphs%s.\n", Time::HiRes::time - $start_time,
            $create ? 'create' : 'update' , $number, $short ? 'short ' : '',
            $rrdcached ? ' with rrdcached' : '');
    }
}

if ($short) {
    if ($create) {
        bench { $rrd->path_short(shift) }
    }
    else {
        bench { my $data = shift; $data->{subtract_short} = int(rand($number)); $rrd->update_short($data) }
    }
}
else {
    if ($create) {
        bench { $rrd->path(shift) }
    }
    else {
        bench { my $data = shift; $data->{subtract} = int(rand($number)); $rrd->update($data) }
    }
}

__END__

=head1 NAME

benchmark_rrd.pl - Benchmark RRD

=head1 SYNOPSIS

$ benchmark_rrd.pl

=head1 DESCRIPTION

    Benchmark RRD

=head1 OPTIONS

=over 3

=item --data-dir

 A directory where sqlite file is stored. Default: `data`.

=item -n --number

 The number of RRD file updated (and created if first time execution). Default: 1.

=item -f --from

 The starting number of RRD file creation or updating. Default: 1

=item -r --repeat

 The number of repititions. Default: 1

=item -p --parallel

 The number of parallel forks. Default: 1 (not implemented yet)

=item -c --create

 Benchmark the creation of RRD files. Default: false, which means benchmark the updating (create RRD files unless already exist)

=item -s --short

 Benchmark the 1min rrd data. Default: false, which means benchmark the normal rrd

=item -m --md5

 Create RRD files of md5ed names as GrowthForecast does. Default: false, which means integer names.

=item -s --daemon

 Specify the rrdcached address. Default: false, which means rrdcached is not used.

=item -h --help

 Display help

=back

AUTHOR
    Naotoshi Seo <sonots {at} gmail.com>

LICENSE
    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

