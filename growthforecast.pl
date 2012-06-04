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
my @allow_from;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'port=s' => \$port,
    'host=s' => \$host,
    'front-proxy=s' => \@front_proxy,
    'allow-from=s' => \@allow_from,
    'disable-1min-metrics' => \my $disable_short,
    'with-mysql=s' => \my $mysql,
    "h|help" => \my $help,
);

if ( $help ) {
    print <<EOF;
usage: $0 --port 5005 --host 127.0.0.1 --front-proxy 127.0.0.1 
          --allow-from 127.0.0.1 --disable-1min-metrics
          --with-mysql dbi:mysql:[dbname];hostname=[localhost]

If you want to use MySQL instead of SQLite, set with-mysql opt with your DSN.
MYSQL_USER,MYSQL_PASSWORD environment values are used as username and password 
for connecting to MySQL.

eg:
  \% MYSQL_USER=www MYSQL_PASSWORD=foobar perl $0 \\
      --with-mysql dbi:mysql:growthforecast;hostname=localhost

GrowthForecast needs CREATE, ALTER, DELETE, INSERT, UPDATE and SELECT privileges

eg:
  mysql> GRANT  CREATE, ALTER, DELETE, INSERT, UPDATE, SELECT \\
         ON growthforecast.* TO 'www'\@'localhost' IDENTIFIED BY foobar;

EOF
    exit(1);
}

if ( $mysql ) {
    eval { require  GrowthForecast::Data::MySQL };
    die "Cannot load MySQL: $@" if $@;
}

my $enable_short = $disable_short ? 0 : 1;
my $root_dir = File::Basename::dirname(__FILE__);
my $sc_board_dir = tempdir( CLEANUP => 1 );
my $scoreboard = Parallel::Scoreboard->new( base_dir => $sc_board_dir );

my $pm = Parallel::Prefork->new({
    max_workers => $enable_short ? 3 : 2,
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
        if ( $running{worker} && ($enable_short ? $running{short_worker} : 1)) {
            local $0 = "$0 (GrowthForecast::Web)";
            $scoreboard->update('web');
            my $web = GrowthForecast::Web->new($root_dir);
            $web->short($enable_short);
            $web->mysql($mysql);
            my $app = builder {
                enable 'Lint';
                enable 'StackTrace';
                if ( @front_proxy ) {
                    enable match_if addr(\@front_proxy), 'ReverseProxy';
                }
                if ( @allow_from ) {
                    enable match_if addr('!',\@allow_from), sub {
                        sub { [403,['Content-Type','text/plain'], ['Forbidden']] }
                    };
                }
                enable 'Static',
                    path => qr!^/(?:(?:css|js|images)/|favicon\.ico$)!,
                    root => $root_dir . '/public';
                enable 'Scope::Container';
                $web->psgi;
            };
             my $loader = Plack::Loader->load(
                 'Starlet',
                 port => $port,
                 host => $host || 0,
                 max_workers => 4,
             );
             $loader->run($app);
        }
        elsif ( $enable_short && !$running{short_worker} ) {
            local $0 = "$0 (GrowthForecast::Worker 1min)";
            $scoreboard->update('short_worker');
            my $worker = GrowthForecast::Worker->new($root_dir);
            $worker->mysql($mysql);
            $worker->run('short');
        }            
        else {
            local $0 = "$0 (GrowthForecast::Worker)";
            $scoreboard->update('worker');
            my $worker = GrowthForecast::Worker->new($root_dir);
            $worker->mysql($mysql);
            $worker->run;
        }
    });
}


