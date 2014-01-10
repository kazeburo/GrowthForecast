package GrowthForecast::Worker;

use strict;
use warnings;
use utf8;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;
use Log::Minimal;
use POSIX ":sys_wait_h";
use Class::Accessor::Lite ( rw => [qw/root_dir data_dir mysql float_number rrdcached disable_subtract/] );
use Scope::Container;

sub new {
    my $class = shift;
    my %args = @_;
    bless \%args, $class;
}

sub data {
    my $self = shift;
    $self->{__data} ||= 
        $self->mysql 
            ? GrowthForecast::Data::MySQL->new($self->mysql, $self->float_number, $self->disable_subtract)
            : GrowthForecast::Data->new($self->data_dir, $self->float_number, $self->disable_subtract);
    $self->{__data};
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new(
        data_dir => $self->data_dir,
        root_dir => $self->root_dir,
        rrdcached => $self->rrdcached,
        disable_subtract => $self->disable_subtract,
    );
    $self->{__rrd};
}

sub run {
    my $self = shift;
    my $method = shift || 'update';
    my $interval = ( $method eq 'update' ) ? 300 : 60;

    local $Log::Minimal::AUTODUMP = 1;

    my @signals_received;
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP/);
    $SIG{PIPE} = 'IGNORE';

    my $now = time;
    my $next = $now - ( $now % $interval )  + $interval;
    my $pid;

    infof( "[%s] first updater start in %s", $method, scalar localtime $next );

    while ( 1 ) {
        select( undef, undef, undef, 0.5 );
        if ( $pid ) {
            my $kid = waitpid( $pid, WNOHANG );
            if ( $kid == -1 ) {
                warnf('no child processes');
                $pid = undef;
            }
            elsif ( $kid ) {
                debugf( "[%s] update finished pid: %d, code:%d", $method, $kid, $? >> 8);
                debugf( "[%s] next radar start in %s",  $method, scalar localtime $next);
                $pid = undef;
            }
        }

        if ( scalar @signals_received ) {
            warnf( "[$method] signals_received:" . join ",",  @signals_received );
            last;
        }

        $now = time;
        if ( $now >= $next ) {
            debugf( "[%s] (%s) updater start ", $method, scalar localtime $next);
            $next = $now - ( $now % $interval ) + $interval;

            if ( $pid ) {
                warnf( "[%s] Previous radar exists, skipping this time", $method);
                next;
            }

            $pid = fork();
            die "failed fork: $!" unless defined $pid;
            next if $pid; #main process

            #child process
            my $container = start_scope_container();
            if ( $self->disable_subtract ) {
                # --disable-subtract makes possible to avoid N+1 queries, yay!
                my $all_rows = $self->data->get_all_graph_all;
                for my $data ( @$all_rows ) {
                    debugf( "[%s] update %s", $method, $data->{id});
                    if ( $method eq 'update' ) {
                        $self->rrd->update($data);
                    }
                    else {
                        $self->rrd->update_short($data);
                    }
                }
            }
            else {
                my $all_rows = $self->data->get_all_graph_id;
                for my $row ( @$all_rows ) {
                    debugf( "[%s] update %s", $method, $row);
                    if ( $method eq 'update' ) {
                        my $data = $self->data->get_by_id_for_rrdupdate($row->{id});
                        $self->rrd->update($data);
                    }
                    else {
                        my $data = $self->data->get_by_id_for_rrdupdate_short($row->{id});
                        $self->rrd->update_short($data);
                    }
                }
            }
            undef $container;
            exit 0;
        }
    }

    if ( $pid ) {
        warnf( "[%s] waiting for updater process finishing",$method );
        waitpid( $pid, 0 );
    }
    
}


1;


