package GrowthForecast::Data;

use strict;
use warnings;
use utf8;
use DBIx::Sunny;
use Time::Piece;
use Digest::MD5 qw/md5_hex/;
use List::Util;
use Encode;
use JSON;
use Log::Minimal;
use List::MoreUtils qw/uniq/;
use List::Util qw/first/;

sub new {
    my $class = shift;
    my $data_dir = shift;
    my $float_number = shift;
    bless { data_dir => $data_dir, float_number => $float_number }, $class;
}

sub number_type {
    my $self = shift;
    return $self->{'float_number'} ? 'REAL' : 'INT';
}

sub on_connect {
    my $self = shift;
    return sub {
        my $dbh = shift;
        my $number_type = $self->number_type;

        $dbh->do('PRAGMA journal_mode = WAL');
        $dbh->do('PRAGMA synchronous = NORMAL');

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS graphs (
    id           INTEGER NOT NULL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL,
    section_name VARCHAR(255) NOT NULL,
    graph_name   VARCHAR(255) NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    mode         VARCHAR(255) NOT NULL DEFAULT 'gauge',
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         UNSIGNED INT NOT NULL DEFAULT 0,
    gmode        VARCHAR(255) NOT NULL DEFAULT 'gauge',
    color        VARCHAR(255) NOT NULL DEFAULT '#00CC00',
    ulimit       $number_type NOT NULL DEFAULT 1000000000000000,
    llimit       $number_type NOT NULL DEFAULT 0,
    sulimit      $number_type NOT NULL DEFAULT 100000,
    sllimit      $number_type NOT NULL DEFAULT 0,
    type         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    stype         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    meta         TEXT,
    created_at   UNSIGNED INT NOT NULL,
    updated_at   UNSIGNED INT NOT NULL,
    UNIQUE  (service_name, section_name, graph_name)
)
EOF

        $dbh->begin_work;
        my $columns = $dbh->select_all(q{PRAGMA table_info("graphs")});
        my %graphs_columns;
        $graphs_columns{$_->{name}} = 1 for @$columns;
        if ( ! exists $graphs_columns{mode} ) {
            infof("add new column 'mode'");
            $dbh->do(q{ALTER TABLE graphs ADD mode VARCHAR(255) NOT NULL DEFAULT 'gauge'});
            $dbh->query(q{UPDATE graphs SET mode='-'});
        }
        $dbh->commit;

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_graphs (
    graph_id     INT NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    subtract     $number_type,
    updated_at   UNSIGNED INT NOT NULL,
    PRIMARY KEY  (graph_id)
)
EOF

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_short_graphs (
    graph_id     INT NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    subtract     $number_type,
    updated_at   UNSIGNED INT NOT NULL,
    PRIMARY KEY  (graph_id)
)
EOF

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS complex_graphs (
    id           INTEGER NOT NULL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL,
    section_name VARCHAR(255) NOT NULL,
    graph_name   VARCHAR(255) NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         UNSIGNED INT NOT NULL DEFAULT 0,
    meta         TEXT,
    created_at   UNSIGNED INT NOT NULL,
    updated_at   UNSIGNED INT NOT NULL,
    UNIQUE  (service_name, section_name, graph_name)
)
EOF
        return;
    };
}

sub dbh {
    my $self = shift;
    $self->{dbh} ||= DBIx::Sunny->connect_cached('dbi:SQLite:dbname='.$self->{data_dir}.'/gforecast.db','','',{
        sqlite_use_immediate_transaction => 1,
        Callbacks => {
            connected => $self->on_connect,
        },
    });
    $self->{dbh};
}

sub inflate_row {
    my ($self, $row) = @_;
    $row->{created_at} = localtime($row->{created_at})->strftime('%Y/%m/%d %T');
    $row->{updated_at} = localtime($row->{updated_at})->strftime('%Y/%m/%d %T');
    $row->{md5} = md5_hex( Encode::encode_utf8($row->{id}) );
    my $ref =  decode_json($row->{meta}||'{}');
    $ref->{adjust} = '*' if ! exists $ref->{adjust};
    $ref->{adjustval} = '1' if ! exists $ref->{adjustval};
    $ref->{unit} = '' if ! exists $ref->{unit};
    my %result = (
        %$ref,
        %$row
    );
    \%result
}

sub get {
    my ($self, $service, $section, $graph) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?',
        $service, $section, $graph
    );
    return unless $row;
    $self->inflate_row($row);
}

sub get_by_id {
    my ($self, $id) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return unless $row;
    $self->inflate_row($row);
}

sub get_by_id_for_rrdupdate_short {
    my ($self, $id) = @_;
    my $dbh = $self->dbh;

    my $data = $dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return if !$data;

    $dbh->begin_work;
    my $subtract;
    my $for_update = ( $dbh->connect_info->[0] =~ /^(?i:dbi):mysql:/ ) ? ' FOR UPDATE' : '';
    my $prev = $dbh->select_row(
        'SELECT * FROM prev_short_graphs WHERE graph_id = ?'.$for_update,
        $data->{id}
    );
    if ( !$prev ) {
        $subtract = 'U';
        $dbh->query(
            'INSERT INTO prev_short_graphs (graph_id, number, subtract, updated_at) 
                         VALUES (?,?,?,?)',
            $data->{id}, $data->{number}, undef, $data->{updated_at});
    }
    elsif ( $data->{updated_at} != $prev->{updated_at} ) {
        $subtract = $data->{number} - $prev->{number};
        $dbh->query(
            'UPDATE prev_short_graphs SET number=?, subtract=?, updated_at=? WHERE graph_id = ?',
            $data->{number}, $subtract, $data->{updated_at}, $data->{id}
        );
    }
    else {
        if ( $data->{mode} eq 'gauge' || $data->{mode} eq 'modified' ) {
            $subtract = $prev->{subtract};
            $subtract = 'U' if ! defined $subtract;
        }
        else {
            $subtract = 0;
        }
    }
    $dbh->commit;
    $data->{subtract_short} = $subtract;
    $self->inflate_row($data);
}

sub get_by_id_for_rrdupdate {
    my ($self, $id) = @_;
    my $dbh = $self->dbh;

    my $data = $dbh->select_row(
        'SELECT * FROM graphs WHERE id = ?',
        $id
    );
    return if !$data;

    $dbh->begin_work;
    my $subtract;

    my $for_update = ( $dbh->connect_info->[0] =~ /^(?i:dbi):mysql:/ ) ? ' FOR UPDATE' : '';
    my $prev = $dbh->select_row(
        'SELECT * FROM prev_graphs WHERE graph_id = ?' . $for_update,
        $data->{id}
    );
    
    if ( !$prev ) {
        $subtract = 'U';
        $dbh->query(
            'INSERT INTO prev_graphs (graph_id, number, subtract, updated_at) 
                         VALUES (?,?,?,?)',
            $data->{id}, $data->{number}, undef, $data->{updated_at});
    }
    elsif ( $data->{updated_at} != $prev->{updated_at} ) {
        $subtract = $data->{number} - $prev->{number};
        $dbh->query(
            'UPDATE prev_graphs SET number=?, subtract=?, updated_at=? WHERE graph_id = ?',
            $data->{number}, $subtract, $data->{updated_at}, $data->{id}
        );        
    }
    else {
        if ( $data->{mode} eq 'gauge' || $data->{mode} eq 'modified' ) {
            $subtract = $prev->{subtract};
            $subtract = 'U' if ! defined $subtract;
        }
        else {
            $subtract = 0;
        }
    }

    $dbh->commit;
    $data->{subtract} = $subtract;
    $self->inflate_row($data);
}

sub update {
    my ($self, $service, $section, $graph, $number, $mode, $color ) = @_;
    my $dbh = $self->dbh;
    $dbh->begin_work;

    my $for_update = ( $dbh->connect_info->[0] =~ /^(?i:dbi):mysql:/ ) ? ' FOR UPDATE' : '';
    my $data = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?' . $for_update,
        $service, $section, $graph
    );

    if ( defined $data ) {
        if ( $mode eq 'count' ) {
            $number += $data->{number};
        }
        if ( $mode ne 'modified' || ($mode eq 'modified' && $data->{number} != $number) ) {
            $color ||= $data->{color};
            $dbh->query(
                'UPDATE graphs SET number=?, mode=?, color=?, updated_at=? WHERE id = ?',
                $number, $mode, $color, time, $data->{id}
            );
        }
    }
    else {
        my @colors = List::Util::shuffle(qw/33 66 99 cc/);
        $color ||= '#' . join('', splice(@colors,0,3));
        $dbh->query(
            'INSERT INTO graphs (service_name, section_name, graph_name, number, mode, color, llimit, sllimit, created_at, updated_at) 
                         VALUES (?,?,?,?,?,?,?,?,?,?)',
            $service, $section, $graph, $number, $mode, $color, -1000000000, -100000 ,time, time
        ); 
    }

    my $row = $self->dbh->select_row(
        'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?',
        $service, $section, $graph
    );

    $dbh->commit;

    $self->inflate_row($row);
}

sub update_graph {
    my ($self, $id, $args) = @_;
    my @update = map { delete $args->{$_} } qw/service_name section_name graph_name description sort gmode color type stype llimit ulimit sllimit sulimit/;
    my $meta = encode_json($args);
    my $dbh = $self->dbh;
    $dbh->query(
        'UPDATE graphs SET service_name=?, section_name=?, graph_name=?, description=?, sort=?, gmode=?, color=?, type=?, stype=?,
         llimit=?, ulimit=?, sllimit=?, sulimit=?, meta=? WHERE id = ?',
        @update, $meta, $id
    );
    return 1;
}

sub update_graph_description {
    my ($self, $id, $description) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'UPDATE graphs SET description=? WHERE id = ?',
        $description, $id
    );
    return 1;    
}

sub get_services {
    my $self = shift;
    my $rows = $self->dbh->select_all(
        'SELECT DISTINCT service_name FROM graphs ORDER BY service_name',
    );
    my $complex_rows = $self->dbh->select_all(
        'SELECT DISTINCT service_name FROM complex_graphs ORDER BY service_name',
    );
    my @names = uniq map { $_->{service_name} } (@$rows,@$complex_rows);
    \@names
}

sub get_sections {
    my $self = shift;
    my $service_name = shift;
    my $rows = $self->dbh->select_all(
        'SELECT DISTINCT section_name FROM graphs WHERE service_name = ? ORDER BY section_name',
        $service_name,
    );
    my $complex_rows = $self->dbh->select_all(
        'SELECT DISTINCT section_name FROM complex_graphs WHERE service_name = ? ORDER BY section_name',
        $service_name,
    );
    my @names = uniq map { $_->{section_name} } (@$rows,@$complex_rows);
    \@names;
} 

sub get_graphs {
   my $self = shift;
   my ($service_name, $section_name) = @_;
   my $rows = $self->dbh->select_all(
       'SELECT * FROM graphs WHERE service_name = ? AND section_name = ? ORDER BY sort DESC',
       $service_name, $section_name
   );
   my $complex_rows = $self->dbh->select_all(
       'SELECT * FROM complex_graphs WHERE service_name = ? AND section_name = ? ORDER BY sort DESC',
       $service_name, $section_name
   );
   my @ret;
   for my $row ( @$rows ) {
       push @ret, $self->inflate_row($row); 
   }
   for my $row ( @$complex_rows ) {
       push @ret, $self->inflate_complex_row($row); 
   }
   @ret = sort { $b->{sort} <=> $a->{sort} } @ret;
   \@ret;
}

sub get_all_graph_id {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id FROM graphs',
   );
}

sub get_all_graph_name {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id,service_name,section_name,graph_name FROM graphs ORDER BY service_name, section_name, graph_name DESC',
   );
}

sub get_all_graph_all {
    my $self = shift;
    my $list = $self->dbh->select_all(
        'SELECT * FROM graphs ORDER BY service_name, section_name, graph_name DESC',
    );
    return [] unless $list;
    my @ret = map { $self->inflate_row($_) } @$list;
    \@ret;
}

sub remove {
    my ($self, $id ) = @_;
    my $dbh = $self->dbh;
    $dbh->begin_work;
    $dbh->query(
        'DELETE FROM graphs WHERE id = ?',
        $id
    );
    $dbh->query(
        'DELETE FROM prev_graphs WHERE graph_id = ?',
        $id
    );
    $dbh->commit;

}

sub inflate_complex_row {
    my ($self, $row) = @_;
    $row->{created_at} = localtime($row->{created_at})->strftime('%Y/%m/%d %T');
    $row->{updated_at} = localtime($row->{updated_at})->strftime('%Y/%m/%d %T');

    my $ref =  decode_json($row->{meta}||'{}');
    my $uri = join ":", map { $ref->{$_} } qw /type-1 path-1 gmode-1/;
    $uri .= ":0"; #stack

    if ( !ref $ref->{'type-2'} ) {
        $ref->{$_} = [$ref->{$_}] for qw /type-2 path-2 gmode-2 stack-2/;
    }
    my $num = scalar @{$ref->{'type-2'}};
    my @ret;
    for ( my $i = 0; $i < $num; $i++ ) {
        $uri .= ':' . join ":", map { $ref->{$_}->[$i] } qw /type-2 path-2 gmode-2 stack-2/;
        push @ret, {
            type => $ref->{'type-2'}->[$i],
            path => $ref->{'path-2'}->[$i],
            gmode => $ref->{'gmode-2'}->[$i],
            stack => $ref->{'stack-2'}->[$i],
            graph => $self->get_by_id($ref->{'path-2'}->[$i]),
        };        
    }

    $ref->{sumup} = 0 if ! exists $ref->{sumup};
    $ref->{data_rows} = \@ret;
    $ref->{complex_graph} = $uri;
    my %result = (
        %$ref,
        %$row
    );
    \%result
}

sub get_complex {
    my ($self, $service, $section, $graph) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM complex_graphs WHERE service_name = ? AND section_name = ? AND graph_name = ?',
        $service, $section, $graph
    );
    return unless $row;
    $self->inflate_complex_row($row);
}

sub get_complex_by_id {
    my ($self, $id) = @_;
    my $row = $self->dbh->select_row(
        'SELECT * FROM complex_graphs WHERE id = ?',
        $id
    );
    return unless $row;
    $self->inflate_complex_row($row);
}

sub create_complex {
    my ($self, $service, $section, $graph, $args) = @_;
    my @update = map { delete $args->{$_} } qw/description sort/;
    my $meta = encode_json($args);
    $self->dbh->query(
        'INSERT INTO complex_graphs (service_name, section_name, graph_name, description, sort, meta,  created_at, updated_at) 
                         VALUES (?,?,?,?,?,?,?,?)',
        $service, $section, $graph, @update, $meta, time, time
    ); 
    $self->get_complex($service, $section, $graph);
}

sub update_complex {
    my ($self, $id, $args) = @_;
    my @update = map { delete $args->{$_} } qw/service_name section_name graph_name description sort/;
    my $meta = encode_json($args);
    $self->dbh->query(
        'UPDATE complex_graphs SET service_name = ?, section_name = ?, graph_name = ? , 
                                   description = ?, sort = ?, meta = ?, updated_at = ?
                             WHERE id=?',
        @update, $meta, time, $id        
    );
    $self->get_complex_by_id($id);
}

sub remove_complex {
    my ($self, $id ) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'DELETE FROM complex_graphs WHERE id = ?',
        $id
    );
}

sub get_all_complex_graph_id {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id FROM complex_graphs',
   );
}

sub get_all_complex_graph_name {
   my $self = shift;
   $self->dbh->select_all(
       'SELECT id,service_name,section_name,graph_name FROM complex_graphs ORDER BY service_name, section_name, graph_name DESC',
   );
}

sub get_all_complex_graph_all {
    my $self = shift;
    my $list = $self->dbh->select_all(
        'SELECT * FROM complex_graphs ORDER BY service_name, section_name, graph_name DESC',
    );
    return [] unless $list;
    my @ret = map { $self->inflate_complex_row($_) } @$list;
    \@ret;
}

1;

