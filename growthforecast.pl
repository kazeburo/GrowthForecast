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
use Plack::Util;
use GrowthForecast;
use GrowthForecast::Web;
use GrowthForecast::Worker;
use IO::Socket::UNIX;
use Proclet;
use Starlet '0.21';
use File::ShareDir qw/dist_dir/;
use Cwd;
use File::Path qw/mkpath/;
use Log::Minimal;
use Pod::Usage;

my $port = 5125;
my $host = 0;
my @front_proxy;
my @allow_from;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'port=s' => \$port,
    'host=s' => \$host,
    'socket=s' => \my $socket,
    'front-proxy=s' => \@front_proxy,
    'allow-from=s' => \@allow_from,
    'disable-1min-metrics' => \my $disable_short,
    'disable-subtract' => \my $disable_subtract,
    'enable-float-number' => \my $enable_float_number,
    'with-mysql=s' => \my $mysql,
    'data-dir=s' => \my $data_dir,
    'log-format=s' => \my $log_format,
    'web-max-workers=i' => \my $web_max_workers,
    'rrdcached=s' => \my $rrdcached,
    'mount=s' => \my $mount,
    "h|help" => \my $help,
);

if ( $help ) {
    pod2usage(-verbose=>2,-exitval=>0);
}

if ( $mysql ) {
    eval { require  GrowthForecast::Data::MySQL };
    die "Cannot load MySQL: $@" if $@;
}

my $root_dir = File::Basename::dirname(__FILE__);
if ( ! -f "$root_dir/lib/GrowthForecast.pm" ) {
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
    open( my $fh, '>', "$data_dir/$$.tmp") or die "cannot create file in data_dir: $!";
    close($fh);
    unlink("$data_dir/$$.tmp");
}

my $sock;
if ( $socket ) {
    if (-S $socket) {
        warn "removing existing socket file:$socket";
        unlink $socket
            or die "failed to remove existing socket file:$socket:$!";
    }
    unlink $socket;
    $sock = IO::Socket::UNIX->new(
        Listen => Socket::SOMAXCONN(),
        Local  => $socket,
    ) or die "failed to listen to file $socket:$!";
    $ENV{SERVER_STARTER_PORT} = $socket."=".$sock->fileno;
}

my $proclet = Proclet->new;
$proclet->service(
    tag  => 'worker_1min',
    code => sub {
        local $0 = "$0 (GrowthForecast::Worker 1min)";
        my $worker = GrowthForecast::Worker->new(
            root_dir => $root_dir,
            data_dir => $data_dir,
            mysql => $mysql,
            float_number => $enable_float_number,
            rrdcached => $rrdcached,
            disable_subtract => $disable_subtract,
        );
        $worker->run('short');        
    }
) if !$disable_short;

$proclet->service(
    tag  => 'worker',
    code => sub {
        local $0 = "$0 (GrowthForecast::Worker)";
        my $worker = GrowthForecast::Worker->new(
            root_dir => $root_dir,
            data_dir => $data_dir,
            mysql => $mysql,
            float_number => $enable_float_number,
            rrdcached => $rrdcached,
            disable_subtract => $disable_subtract,
        );
        $worker->run;
    }
);

$proclet->service(
    tag  => 'web',
    code => sub {
        local $0 = "$0 (GrowthForecast::Web)";
        my $web = GrowthForecast::Web->new(
            root_dir => $root_dir,
            data_dir => $data_dir,
            short => !$disable_short,
            mysql => $mysql,
            float_number => $enable_float_number,
            rrdcached => $rrdcached,
            disable_subtract => $disable_subtract,
        );
        my $app = builder {
            enable 'Lint';
            enable 'StackTrace';
            if ( $sock ) {
                enable 'ReverseProxy';
            }
            elsif ( @front_proxy ) {
                enable match_if addr(\@front_proxy), 'ReverseProxy';
            }
            if ( @allow_from ) {
                enable match_if addr('!',\@allow_from), sub {
                    sub { [403,['Content-Type','text/plain'], ['Forbidden']] }
                };
            }
            enable sub {
                my $app = shift;
                sub {
                    my $env = shift;
                    my $res = $app->($env);
                    Plack::Util::response_cb($res, sub {
                                                 my $res = shift;
                                                 Plack::Util::header_set($res->[1], 'X-Powered-By', 
                                                                         'GrowthForecast/'.$GrowthForecast::VERSION);
                                             });
                }
            };
            my $static_regexp = qr!^/(?:(?:css|fonts|js|images)/|favicon\.ico$)!;
            enable 'Static',
                path => $mount ? sub { s!^/$mount!!; $_ =~ $static_regexp } : $static_regexp,
                root => $root_dir . '/public';
            enable 'Scope::Container';
            if ($log_format) {
                my %args;
                if ($log_format eq 'combined') {
                    %args = (combined => 1);
                }
                elsif ($log_format eq 'ltsv') {
                    %args = (ltsv => 1);
                }
                else {
                    %args = (format => $log_format);
                }
                enable 'AxsLog', %args;
            }
            if ($mount) {
                mount "/$mount" => $web->psgi;
            }
            else {
                $web->psgi;
            }
        };
        my $loader = Plack::Loader->load(
            'Starlet',
            port => $port,
            host => $host || 0,
            max_workers => $web_max_workers || 4,
        );
        infof( "GrowthForecast::Web starts listen on %s:%s", $host || 0, $port );
        $loader->run($app);
    }
);


$proclet->run;

__END__

=head1 NAME

growthforecast.pl - Lightning Fast Graphing/Visualization

=head1 SYNOPSIS

  % growthforecast.pl --data-dir=/path/to/dir

=head1 DESCRIPTION

GrowthForecast is graphing/visualization web tool built on RRDtool

=head1 INSTALL

=over 4

=item Install dependencies

To install growthforecast, these libraries are needed.

=over 4

=item * glib

=item * xml2

=item * pango

=item * cairo

=back

  (CentOS) $ sudo yum groupinstall "Development Tools"
           $ sudo yum install pkgconfig glib2-devel gettext libxml2-devel pango-devel cairo-devel
  
  (Ubuntu) $ sudo apt-get build-dep rrdtool

=item Install GrowthForecast

  $ cpanm GrowthForecast

It's recommended to using perlbrew

=back

=head1 OPTIONS

=over 4

=item --data-dir

A directory to store rrddata and metadata

=item --port

TCP port listen on. Default is 5125

=item --host

IP address to listen on

=item --socket

File path to UNIX domain socket to bind. If enabled unix domain socket, GrowthForecast does not bind any TCP port

=item --front-proxy

IP addresses or CIDR of reverse proxy

=item --allow-from

IP addresses or CIDR to allow access from.
Default is empty (allow access from any remote ip address)

=item --disable-1min-metrics

don't generate 1min rrddata and graph
Default is "1" (enabled) 

=item --disable-subtract

Disable gmode `subtract`. Default is "1" (enabled)

=item --enable-float-number

Store numbers of graph data as float rather than integer.
Default is "0" (disabled)

=item --with-mysql

DB connection setting to store  metadata. format like dbi:mysql:[dbname];hostname=[hostnaem]
Default is no mysql setting. GrowthForecast save metadata to SQLite

=item --web-max-workers

Number of web server processes. Default is 4

=item --rrdcached

rrdcached address. format is like either of

   unix:</path/to/unix.sock>
   /<path/to/unix.sock>
   <hostname-or-ip>
   [<hostname-or-ip>]:<port>
   <hostname-or-ipv4>:<port>

See the manual of rrdcached for more details. Default does not use rrdcached.

=item --mount

Provide GrowthForecast with specify url path.
Default is empty ( provide GrowthForecast on root path )

=item -h --help

Display help

=back

=head1 MYSQL Setting

GrowthForecast uses SQLite as metadata by default. And also supports MySQL

GrowthForecast needs these MySQL privileges.

=over 4

=item * CREATE

=item * ALTER

=item * DELETE

=item * INSERT

=item * UPDATE

=item * SELECT

=back

Sample GRANT statement

  mysql> GRANT statement sample> GRANT  CREATE, ALTER, DELETE, INSERT, UPDATE, SELECT \\
           ON growthforecast.* TO 'www'\@'localhost' IDENTIFIED BY foobar;

Give USERNAME and PASSWORD to GrowthForecast by environment value

  $ MYSQL_USER=www MYSQL_PASSWORD=foobar growthforecast.pl \\
      --data-dir /home/user/growthforeacst \\
      -with-mysql dbi:mysql:growthforecast;hostname=localhost 

AUTHOR
    Masahiro Nagano <kazeburo {at} gmail.com>

LICENSE
    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.


