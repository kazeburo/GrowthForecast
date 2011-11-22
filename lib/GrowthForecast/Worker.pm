package GrowthForecast::Worker;

use strict;
use warnings;
use utf8;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;
use Log::Minimal;
use POSIX ":sys_wait_h";

sub new {
    my $class = shift;
    my $root_dir = shift;
    bless { root_dir => $root_dir }, $class;
}

sub data {
    my $self = shift;
    $self->{__data} ||= GrowthForecast::Data->new($self->{root_dir});
    $self->{__data};
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new($self->{root_dir});
    $self->{__rrd};
}

sub run {
    my $self = shift;

    local $Log::Minimal::AUTODUMP = 1;

    my @signals_received;
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP/);
    $SIG{PIPE} = 'IGNORE';

    my $now = time;
    my $next = $now - ( $now % 300 )  + 300;
    my $pid;

    infof( sprintf( "first updater start in %s", scalar localtime $next) );

    while ( 1 ) {
        select( undef, undef, undef, 0.5 );
        if ( $pid ) {
            my $kid = waitpid( $pid, WNOHANG );
            if ( $kid == -1 ) {
                warnf('no child processes');
                $pid = undef;
            }
            elsif ( $kid ) {
                debugf( sprintf("update finished pid: %d, code:%d", $kid, $? >> 8) );
                debugf( sprintf( "next radar start in %s", scalar localtime $next) );
                $pid = undef;
            }
        }

        if ( scalar @signals_received ) {
            warnf( "signals_received:" . join ",",  @signals_received );
            last;
        }

        $now = time;
        if ( $now >= $next ) {
            debugf( sprintf( "(%s) updater start ", scalar localtime $next) );
            $next = $now - ( $now % 300 ) + 300;

            if ( $pid ) {
                warnf( "Previous radar exists, skipping this time");
                next;
            }

            $pid = fork();
            die "failed fork: $!" unless defined $pid;
            next if $pid; #main process

            #child process
            my $all_rows = $self->data->get_all_graphs;
            for my $row ( @$all_rows ) {
                debugf( "update %s", $row);
                my $data = $self->data->get_for_rrdupdate($row->{service_name},$row->{section_name},$row->{graph_name});
                $self->rrd->update($data);
            }
            exit 0;
        }
    }

    if ( $pid ) {
        warnf( "waiting for updater process finishing" );
        waitpid( $pid, 0 );
    }
    
}


1;


