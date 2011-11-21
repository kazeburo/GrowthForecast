#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use GrowthForecast::Worker;

my $root_dir = File::Basename::dirname(__FILE__);

my $worker = GrowthForecast::Worker->new($root_dir);
$worker->run;


