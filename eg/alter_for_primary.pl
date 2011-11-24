#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use utf8;
use DBIx::Sunny;
use Encode;
use File::Copy;
use Digest::MD5 qw/md5_hex/;

my $root_dir = "$FindBin::Bin/..";
my $dbh = DBIx::Sunny->connect_cached('dbi:SQLite:dbname='.$root_dir.'/data.o/gforecast.db','','',{
    sqlite_use_immediate_transaction => 1,
});

$dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS graphs_new (
    id           INTEGER NOT NULL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL,
    section_name VARCHAR(255) NOT NULL,
    graph_name   VARCHAR(255) NOT NULL,
    number       INT NOT NULL DEFAULT 0,
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         UNSIGNED INT NOT NULL DEFAULT 0,
    gmode        VARCHAR(255) NOT NULL DEFAULT 'gauge',
    color        VARCHAR(255) NOT NULL DEFAULT '#00CC00',
    ulimit       INT NOT NULL DEFAULT 1000000000,
    llimit       INT NOT NULL DEFAULT 0,
    sulimit       INT NOT NULL DEFAULT 100000,
    sllimit       INT NOT NULL DEFAULT 0,
    type         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    stype         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    meta         TEXT NOT NULL DEFAULT '',
    created_at   UNSIGNED INT NOT NULL,
    updated_at   UNSIGNED INT NOT NULL,
    UNIQUE  (service_name, section_name, graph_name)
)
EOF

$dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_graphs_new (
    graph_id     INT NOT NULL,
    number       INT NOT NULL DEFAULT 0,
    subtract     INT,
    updated_at   UNSIGNED INT NOT NULL,
    PRIMARY KEY  (graph_id)
)
EOF

my $rows =  $dbh->select_all('SELECT * FROM graphs');
foreach my $old ( @$rows ) {
    $dbh->query(
        'INSERT INTO graphs_new (service_name, section_name, graph_name, 
                             number, description, sort,  gmode, color, ulimit, llimit, 
                             sulimit, sllimit, type, stype, created_at, updated_at) 
                     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        map { $old->{$_} }
            qw/service_name section_name graph_name number description sort gmode color ulimit llimit sulimit sllimit type stype created_at updated_at/
        );
    my $id = $dbh->last_insert_id;
    my $old_prev = $dbh->select_row('SELECT * FROM prev_graphs WHERE service_name=? AND section_name=? AND graph_name=?',
                                $old->{service_name}, $old->{section_name}, $old->{graph_name} );
    if ($old_prev) {
        $dbh->query('INSERT INTO prev_graphs_new (graph_id, number, subtract, updated_at) VALUES (?,?,?,?)',
                    $id, $old_prev->{number}, $old_prev->{subtract}, $old_prev->{updated_at});
    }
}

$dbh->query('DROP TABLE graphs');
$dbh->query('DROP TABLE prev_graphs');

$dbh->query('ALTER TABLE graphs_new RENAME to graphs');
$dbh->query('ALTER TABLE prev_graphs_new RENAME to prev_graphs');

my $rows_new =  $dbh->select_all('SELECT * FROM graphs');
foreach my $row ( @$rows_new ) {
    my $old = md5_hex( join(':',map { Encode::encode_utf8($_) } $row->{service_name},$row->{section_name},$row->{graph_name}) );
    my $new = md5_hex( Encode::encode_utf8($row->{id}) );
    move( "$root_dir/data.o/$old.rrd","$root_dir/data.o/$new.rrd");
}
