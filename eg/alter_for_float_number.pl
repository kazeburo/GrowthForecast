#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../extlib/lib/perl5";
use lib "$FindBin::Bin/../lib";
use File::Basename;
use Getopt::Long;
use GrowthForecast;
use GrowthForecast::Data;
use File::ShareDir qw/dist_dir/;
use Cwd;
use File::Path qw/mkpath/;
use Log::Minimal;
use Pod::Usage;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'data-dir=s' => \my $data_dir,
    'with-mysql=s' => \my $mysql,
    'disable-subtract' => \my $disable_subtract,
    "h|help" => \my $help,
);

if ( $help ) {
    pod2usage(-verbose=>2,-exitval=>0);
}

if ( $mysql ) {
    eval { require  GrowthForecast::Data::MySQL };
    die "Cannot load MySQL: $@" if $@;
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

my $enable_float_number = 1;
my $data = $mysql
    ? GrowthForecast::Data::MySQL->new($mysql, $enable_float_number, $disable_subtract)
    : GrowthForecast::Data->new($data_dir, $enable_float_number, $disable_subtract);

if ($mysql) {
    my $number_type = $data->number_type;
    my $complex_number_type = $data->complex_number_type;
    unless ( $disable_subtract ) {
        $data->dbh->query(<<EOF);
ALTER TABLE prev_graphs
    MODIFY COLUMN number   $number_type NOT NULL DEFAULT 0,
    MODIFY COLUMN subtract $number_type
EOF
        $data->dbh->query(<<EOF);
ALTER TABLE prev_short_graphs
    MODIFY COLUMN number   $number_type NOT NULL DEFAULT 0,
    MODIFY COLUMN subtract $number_type
EOF
    }
    $data->dbh->query(<<EOF);
ALTER TABLE graphs
    MODIFY COLUMN number  $number_type NOT NULL DEFAULT 0,
    MODIFY COLUMN ulimit  $number_type NOT NULL DEFAULT 1000000000000000,
    MODIFY COLUMN llimit  $number_type NOT NULL DEFAULT 0,
    MODIFY COLUMN sulimit $number_type NOT NULL DEFAULT 100000,
    MODIFY COLUMN sllimit $number_type NOT NULL DEFAULT 0
EOF
    $data->dbh->query(<<EOF);
ALTER TABLE complex_graphs
    MODIFY COLUMN number   $complex_number_type UNSIGNED NOT NULL DEFAULT 0
EOF
}
else {
    # NOTE: sqlite does not support `ALTER TABLE MODIFY COLUMN`.
    unless ( $disable_subtract ) {
        $data->dbh->query('ALTER TABLE prev_graphs RENAME TO tmp_prev_graphs');
        $data->dbh->query('ALTER TABLE prev_short_graphs RENAME TO tmp_prev_short_graphs');
    }
    $data->dbh->query('ALTER TABLE graphs RENAME TO tmp_graphs');
    $data->dbh->query('ALTER TABLE complex_graphs RENAME TO tmp_complex_graphs');
    undef($data->{dbh}); # To re-create tables by calling on_connect callback
    unless ( $disable_subtract ) {
        $data->dbh->query('INSERT INTO prev_graphs SELECT * from tmp_prev_graphs');
        $data->dbh->query('INSERT INTO prev_short_graphs SELECT * from tmp_prev_short_graphs');
        $data->dbh->query('DROP TABLE tmp_prev_graphs');
        $data->dbh->query('DROP TABLE tmp_prev_short_graphs');
    }
    $data->dbh->query('INSERT INTO graphs SELECT * from tmp_graphs');
    $data->dbh->query('DROP TABLE tmp_graphs');
    $data->dbh->query('INSERT INTO complex_graphs SELECT * from tmp_complex_graphs');
    $data->dbh->query('DROP TABLE tmp_complex_graphs');
}

__END__

=head1 NAME

alter_for_float_number.pl - alter table to use float number

=head1 SYNOPSIS

$ alter_for_float_number.pl

=head1 DESCRIPTION

    Alter SQLite or MySQL table to use --enable-float-number option.

    CAUTION:
    PLEASE TAKE A BACKUP BEFORE YOU EXECUTE THIS SCRIPT.
    I (the author) shall not owe any responsibilities for your loss.

=head1 OPTIONS

=over 3

=item --data-dir

 A directory where sqlite file is stored. Default is `data`.

=item --with-mysql

 Specify DB connection setting to store metadata if you want to execute migration on MySQL.
 Format like dbi:mysql:[dbname];hostname=[hostname]. GrowthForecast saves metadata to SQLite as default.

 $ MYSQL_USER=www MYSQL_PASSWORD=foobar alter_for_float_number.pl \\
     --with-mysql dbi:mysql:growthforecast;hostname=localhost

=item --disable-subtract

 Specify if your GrowthForecast is using --disable-subtract option.

=item -h --help

 Display help

=back

AUTHOR
    Naotoshi Seo <sonots {at} gmail.com>

LICENSE
    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

