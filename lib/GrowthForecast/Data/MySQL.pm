package GrowthForecast::Data::MySQL;

use strict;
use warnings;
use base qw/GrowthForecast::Data/;
use Scope::Container::DBI;
use Log::Minimal;

sub new {
    my $class = shift;
    my $mysql = shift;
    my $float_number = shift;
    my $disable_subtract = shift;
    bless { mysql => $mysql, float_number => $float_number, disable_subtract => $disable_subtract }, $class;
}

sub number_type {
    my $self = shift;
    return $self->{'float_number'} ? 'DOUBLE' : 'BIGINT';
}

sub complex_number_type {
    my $self = shift;
    return $self->{'float_number'} ? 'FLOAT' : 'INT';
}

sub on_connect {
    my $self = shift;
    return sub {
        my $dbh = shift;
        my $number_type = $self->number_type;
        my $complex_number_type = $self->complex_number_type;

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS graphs (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    section_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    graph_name   VARCHAR(255) NOT NULL COLLATE utf8_bin,
    number       $number_type NOT NULL DEFAULT 0,
    mode         VARCHAR(255) NOT NULL DEFAULT 'gauge',
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         INT UNSIGNED NOT NULL DEFAULT 0,
    gmode        VARCHAR(255) NOT NULL DEFAULT 'gauge',
    color        VARCHAR(255) NOT NULL DEFAULT '#00CC00',
    ulimit       $number_type NOT NULL DEFAULT 1000000000000000,
    llimit       $number_type NOT NULL DEFAULT 0,
    sulimit      $number_type NOT NULL DEFAULT 100000,
    sllimit      $number_type NOT NULL DEFAULT 0,
    type         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    stype        VARCHAR(255) NOT NULL DEFAULT 'AREA',
    meta         TEXT,
    created_at   INT UNSIGNED NOT NULL,
    updated_at   INT UNSIGNED NOT NULL,
    timestamp    INT UNSIGNED DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE  (service_name, section_name, graph_name)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

        unless ( $self->{disable_subtract} ) {
            $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_graphs (
    graph_id     INT UNSIGNED NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    subtract     $number_type,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

            $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_short_graphs (
    graph_id     INT UNSIGNED NOT NULL,
    number       $number_type NOT NULL DEFAULT 0,
    subtract     $number_type,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF
        }

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS complex_graphs (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    section_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    graph_name   VARCHAR(255) NOT NULL COLLATE utf8_bin,
    number       $complex_number_type UNSIGNED NOT NULL DEFAULT 0,
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         INT UNSIGNED NOT NULL DEFAULT 0,
    meta         TEXT,
    created_at   INT UNSIGNED NOT NULL,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE  (service_name, section_name, graph_name)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS vrules (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    graph_path   VARCHAR(255) NOT NULL COLLATE utf8_bin,
    time         INT UNSIGNED NOT NULL,
    color        VARCHAR(255) NOT NULL DEFAULT '#FF0000',
    description  TEXT,
    dashes       VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    INDEX time_graph_path (time, graph_path)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

        {
            my $sth = $dbh->column_info(undef,undef,"vrules",undef);
            my $columns = $sth->fetchall_arrayref(+{ COLUMN_NAME => 1 });
            my %graphs_columns;
            $graphs_columns{$_->{COLUMN_NAME}} = 1 for @$columns;
            if ( ! exists $graphs_columns{dashes} ) {
                infof("add new column 'dashes'");
                $dbh->do(q{ALTER TABLE vrules ADD dashes VARCHAR(255) NOT NULL DEFAULT ''});
            }
        }

        # timestamp
        {
            my $sth = $dbh->column_info(undef,undef,"graphs",undef);
            my $columns = $sth->fetchall_arrayref(+{ COLUMN_NAME => 1 });
            my %graphs_columns;
            $graphs_columns{$_->{COLUMN_NAME}} = 1 for @$columns;
            if ( ! exists $graphs_columns{timestamp} ) {
                infof("add new column 'timestamp'");
                $dbh->do(q{ALTER TABLE graphs ADD timestamp INT UNSIGNED DEFAULT NULL});
            }
        }

        return;
    };
}

sub dbh {
    my $self = shift;
    local $Scope::Container::DBI::DBI_CLASS = 'DBIx::Sunny';
    Scope::Container::DBI->connect(
        $self->{mysql},
        $ENV{MYSQL_USER},
        $ENV{MYSQL_PASSWORD},
        {
            Callbacks => {
                connected => $self->on_connect,
            },
        }
    );
}


1;

