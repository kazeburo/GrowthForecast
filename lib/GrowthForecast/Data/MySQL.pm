package GrowthForecast::Data::MySQL;

use strict;
use warnings;
use base qw/GrowthForecast::Data/;
use Scope::Container::DBI;

sub new {
    my $class = shift;
    my $mysql = shift;
    bless { mysql => $mysql }, $class;
}

sub on_connect {
    my $self = shift;
    return sub {
        my $dbh = shift;

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS graphs (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    section_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    graph_name   VARCHAR(255) NOT NULL COLLATE utf8_bin,
    number       BIGINT NOT NULL DEFAULT 0,
    mode         VARCHAR(255) NOT NULL DEFAULT 'gauge',
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         INT UNSIGNED NOT NULL DEFAULT 0,
    gmode        VARCHAR(255) NOT NULL DEFAULT 'gauge',
    color        VARCHAR(255) NOT NULL DEFAULT '#00CC00',
    ulimit       BIGINT NOT NULL DEFAULT 1000000000,
    llimit       BIGINT NOT NULL DEFAULT 0,
    sulimit      BIGINT NOT NULL DEFAULT 100000,
    sllimit      BIGINT NOT NULL DEFAULT 0,
    type         VARCHAR(255) NOT NULL DEFAULT 'AREA',
    stype        VARCHAR(255) NOT NULL DEFAULT 'AREA',
    meta         TEXT NOT NULL DEFAULT '',
    created_at   INT UNSIGNED NOT NULL,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE  (service_name, section_name, graph_name)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_graphs (
    graph_id     INT UNSIGNED NOT NULL,
    number       BIGINT NOT NULL DEFAULT 0,
    subtract     BIGINT,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF

        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS prev_short_graphs (
    graph_id     INT UNSIGNED NOT NULL,
    number       BIGINT NOT NULL DEFAULT 0,
    subtract     BIGINT,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY  (graph_id)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF


        $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS complex_graphs (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    section_name VARCHAR(255) NOT NULL COLLATE utf8_bin,
    graph_name   VARCHAR(255) NOT NULL COLLATE utf8_bin,
    number       INT UNSIGNED NOT NULL DEFAULT 0,
    description  VARCHAR(255) NOT NULL DEFAULT '',
    sort         INT UNSIGNED NOT NULL DEFAULT 0,
    meta         TEXT NOT NULL DEFAULT '',
    created_at   INT UNSIGNED NOT NULL,
    updated_at   INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE  (service_name, section_name, graph_name)
)  ENGINE=InnoDB DEFAULT CHARSET=utf8
EOF
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

