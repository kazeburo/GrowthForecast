package GrowthForecast::RRD;

use strict;
use warnings;
use utf8;
use RRDs;
use HTTP::Date;
use File::Temp;
use File::Zglob;

sub new {
    my $class = shift;
    my $root_dir = shift;
    bless { root_dir => $root_dir }, $class;
}

sub path {
    my $self = shift;
    my $data = shift;
    my $file = $self->{root_dir} . '/data/' . $data->{md5} . '.rrd';
    if ( ! -f $file ) {
        eval {
            RRDs::create(
                $file,
                '--step', '60',
                'DS:num:GAUGE:600:0:U',
                'RRA:AVERAGE:0.5:1:11520',
                'RRA:AVERAGE:0.5:30:1536',
                'RRA:AVERAGE:0.5:120:768',
                'RRA:AVERAGE:0.5:1440:794',
                'RRA:MAX:0.5:30:1536',
                'RRA:MAX:0.5:120:768',
                'RRA:MAX:0.5:1440:794'
            );
            my $ERR=RRDs::error;
            die $ERR if $ERR;
        };
        die "init failed: $@" if $@;
    }
    $file;
}

sub update {
    my $self = shift;
    my $data = shift;

    my $file = $self->path($data);
    eval {
        RRDs::update(
            $file,
            '-t', 'num',
            '--', 'N:'.$data->{number},
        );
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    die "udpate rrdfile failed: $@" if $@;
}


my @jp_fonts = map { -f $_ } zglob("/usr/share/fonts/**/*-gothic.ttf");
sub graph {
    my $self = shift;
    my ($span, $from, $to, @datas) = @_;
    $span ||= 'd';

    my $period_title;
    my $period;
    my $end = 'now';
    my $xgrid;
    if ( $span eq 'c' ) {
        my $from_time = HTTP::Date::str2time($from);  
        die "invalid from date: $from" unless $from_time;
        my $to_time = $to ? HTTP::Date::str2time($to) : time;
        die "invalid to date: $to" unless $to_time;
        die "from($from) is newer than to($to)" if $from_time > $to_time;

        $period_title = "$from to $to" ;
        $period = $from_time;
        $end = $to_time;
        my $diff = $to_time - $from_time;
        if ( $diff < 3 * 60 * 60 ) {
            $xgrid = 'MINUTE:10:MINUTE:10:MINUTE:10:0:%M';
        }
        elsif ( $diff < 2 * 24 * 60 * 60 ) {
            $xgrid = 'HOUR:1:HOUR:1:HOUR:2:0:%H';
        }
        elsif ( $diff < 14 * 24 * 60 * 60) {
            $xgrid = 'DAY:1:DAY:1:DAY:2:86400:%m/%d';
        }
        elsif ( $diff < 45 * 24 * 60 * 60) {
            $xgrid = 'DAY:1:WEEK:1:WEEK:1:0:%F';
        }
        else {
            $xgrid = 'WEEK:1:MONTH:1:MONTH:1:2592000:%b';
        }
    }
    elsif ( $span eq 'h' ) {
        $period_title = 'Hourly';
        $period = -1 * 60 * 60 * 2;
        $xgrid = 'MINUTE:10:MINUTE:10:MINUTE:10:0:%M';
    }
    elsif ( $span eq 'w' ) {
        $period_title = 'Weekly';
        $period = -1 * 60 * 60 * 24 * 8;
        $xgrid = 'DAY:1:DAY:1:DAY:1:86400:%a'
    }
    elsif ( $span eq 'm' ) {
        $period_title = 'Monthly';
        $period = -1 * 60 * 60 * 24 * 35;
        $xgrid = 'DAY:1:WEEK:1:WEEK:1:604800:Week %W'
    }
    elsif ( $span eq 'y' ) {
        $period_title = 'Yearly';
        $period = -1 * 60 * 60 * 24 * 400;
        $xgrid = 'WEEK:1:MONTH:1:MONTH:1:2592000:%b'
    }
    else {
        $period_title = 'Daily';
        $period = -1 * 60 * 60 * 33; # 33 hours
        $xgrid = 'HOUR:1:HOUR:2:HOUR:2:0:%H';
    }

    my ($tmpfh, $tmpfile) = File::Temp::tempfile(UNLINK => 0, SUFFIX => ".png");
    my @args = (
        $tmpfile,
        '-w', 385,
        '-h', 110,
        '-a', 'PNG',
        '-t', "$period_title",
        '-l', 0, #minimum
        '-u', 2, #maximum
        '-x', $xgrid,
        '-s', $period,
        '-e', $end,
    );

    push @args, '--font', "DEFAULT:0:".$jp_fonts[0] if @jp_fonts;

    my $i=0;
    for my $data ( @datas ) {
        my $type = ( $i == 0 ) ? $data->{type} : 'STACK';
        my $file = $self->path($data);
        push @args, 
            sprintf('DEF:num%dt=%s:num:AVERAGE', $i, $file),
            sprintf('CDEF:num%d=num%dt,%s,%s,LIMIT', $i, $i, $data->{llimit}, $data->{ulimit}),
            sprintf('%s:num%d%s:%s ', $type, $i, $data->{color}, $data->{graph_name}),
            sprintf('GPRINT:num%d:LAST:Cur\: %%4.1lf', $i),
            sprintf('GPRINT:num%d:AVERAGE:Ave\: %%4.1lf', $i),
            sprintf('GPRINT:num%d:MAX:Max\: %%4.1lf', $i),
            sprintf('GPRINT:num%d:MIN:Min\: %%4.1lf\l',$i);
        $i++;
    }

    use Log::Minimal;
    local $Log::Minimal::AUTODUMP = 1;

    eval {
        RRDs::graph(map { Encode::encode_utf8($_) } @args);
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    if ( $@ ) {
        unlink($tmpfile);
        die "draw graph failed: $@";
    }

    open( my $fh, '<:bytes', $tmpfile ) or die "cannot open graph tmpfile: $!";
    local $/;
    my $graph_img = <$fh>;
    unlink($tmpfile);

    die 'something wrong with image' unless $graph_img;

    return $graph_img;    
}

1;


