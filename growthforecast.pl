#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Getopt::Long;
use Plack::Loader;
use Plack::Builder;
use Plack::Builder::Conditionals;
use GrowthForecast::Web;
use GrowthForecast::Worker;
use Proclet;
use File::ShareDir qw/dist_dir/;
use Cwd;
use File::Path qw/mkpath/;

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
    'data-dir=s' => \my $data_dir,
    "h|help" => \my $help,
);

if ( $help ) {
    print <<EOF;
usage: $0 --port 5005 --host 127.0.0.1 --front-proxy 127.0.0.1 
          --allow-from 127.0.0.1
          --disable-1min-metrics
          --data-dir dir
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

my $root_dir = File::Basename::dirname(__FILE__);
if ( ! -f "$root_dir/lib/growthforecast.pm" ) {
    $root_dir = dist_dir('GrowthForecast');
}
if ( !$data_dir ) {
    $data_dir = $root_dir . '/data';
}
else {
    $data_dir = Cwd::realpath($data_dir);
}

{
    if ( ! -d $data_dir ) {
        mkpath($data_dir) or die "cannot create data directory '$data_dir': $!";
    }
    open( my $fh, '>', "$data_dir/$$.tmp") or die 'cannot create file in data_dir: $!';
    close($fh);
    unlink("$data_dir/$$.tmp");
}

my $proclet = Proclet->new;
$proclet->service(
    code => sub {
        local $0 = "$0 (GrowthForecast::Worker 1min)";
        my $worker = GrowthForecast::Worker->new(
            data_dir => $data_dir,
            mysql => $mysql,
        );
        $worker->run('short');        
    }
) if !$disable_short;

$proclet->service(
    code => sub {
        local $0 = "$0 (GrowthForecast::Worker)";
        my $worker = GrowthForecast::Worker->new(
            data_dir => $data_dir,
            mysql => $mysql
        );
        $worker->run;
    }
);

$proclet->service(
    code => sub {
        local $0 = "$0 (GrowthForecast::Web)";
        my $web = GrowthForecast::Web->new(
            root_dir => $root_dir,
            data_dir => $data_dir,
            short => !$disable_short,
            mysql => $mysql,
        );
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
);


$proclet->run;

