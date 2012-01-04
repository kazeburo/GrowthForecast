#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Getopt::Long;
use File::Temp qw/tempdir/;
use Parallel::Prefork;
use Parallel::Scoreboard;
use Plack::Loader;
use Plack::Builder;
use Plack::Builder::Conditionals;
use GrowthForecast::Web;
use GrowthForecast::Worker;

my $port = 5125;
my $host = 0;
my @front_proxy;
my @allowfrom;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'port=s' => \$port,
    'host=s' => \$host,
    'front-proxy=s' => \@front_proxy,
    'allow-from=s' => \@allowfrom,
    "h|help" => \my $help,
);

if ( $help ) {
    print "usage: $0 --port 5005 --host 127.0.0.1 --front-proxy 127.0.0.1\n";
    exit(1);
}

my $root_dir = File::Basename::dirname(__FILE__);
my $sc_board_dir = tempdir( CLEANUP => 1 );
my $scoreboard = Parallel::Scoreboard->new( base_dir => $sc_board_dir );

my $pm = Parallel::Prefork->new({
    max_workers => 2,
    spawn_interval  => 1,
    trap_signals    => {
        map { ($_ => 'TERM') } qw(TERM HUP)
    }
});

while ($pm->signal_received ne 'TERM' ) {
    $pm->start(sub{
        my $stats = $scoreboard->read_all;
        my %running;
        for my $pid ( keys %{$stats} ) {
            my $val = $stats->{$pid};
            $running{$val}++;
        }
        if ( $running{worker} ) {
            local $0 = "$0 (GrowthForecast::Web)";
            $scoreboard->update('web');
            my $app = GrowthForecast::Web->psgi($root_dir);
            $app = builder {
                enable 'Lint';
                enable 'StackTrace';
                if ( @front_proxy ) {
                    enable match_if addr(\@front_proxy), 'ReverseProxy';
                }
                if ( @allowfrom ) {
                    my @rule;
                    for ( @allowfrom ) {
                        push @rule, 'allow', $_;
                    }
                    push @rule, 'deny', 'all';
                    enable 'Plack::Middleware::Access', rules => \@rule;
                }
                enable 'Static',
                    path => qr!^/(?:(?:css|js|images)/|favicon\.ico$)!,
                    root => $root_dir . '/public';
                $app;
            };
             my $loader = Plack::Loader->load(
                 'Starlet',
                 port => $port,
                 host => $host || 0,
                 max_workers => 4,
             );
             $loader->run($app);
        }
        else {
            local $0 = "$0 (GrowthForecast::Worker)";
            $scoreboard->update('worker');
            my $worker = GrowthForecast::Worker->new($root_dir);
            $worker->run;
        }
    });
}


