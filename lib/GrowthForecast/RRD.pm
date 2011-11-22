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
                '--step', '300',
                'DS:num:GAUGE:600:U:U',
                'DS:sub:GAUGE:600:U:U', 
                'RRA:AVERAGE:0.5:1:1440',  #5分, 5日
                'RRA:AVERAGE:0.5:6:1008', #30分, 21日
                'RRA:AVERAGE:0.5:24:1344', #2時間, 112日 
                'RRA:AVERAGE:0.5:288:2500', #24時間, 500日
                'RRA:MAX:0.5:1:1440',  #5分, 5日
                'RRA:MAX:0.5:6:1008', #30分, 21日
                'RRA:MAX:0.5:24:1344', #2時間, 112日 
                'RRA:MAX:0.5:288:2500', #24時間, 500日
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
            '-t', 'num:sub',
            '--', join(':','N',$data->{number},$data->{subtract}),
        );
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    die "udpate rrdfile failed: $@" if $@;
}


my @jp_fonts = grep { -f $_ } zglob("/usr/share/fonts/**/sazanami-gothic.ttf");
sub graph {
    my $self = shift;
    my ($gmode, $span, $from, $to, $data) = @_;
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
            $xgrid = 'MINUTE:10:MINUTE:20:MINUTE:10:0:%M';
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
        $xgrid = 'MINUTE:10:MINUTE:20:MINUTE:10:0:%M';
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

    if ( $gmode eq 'subtract' ) { $period_title = "[subtract] $period_title" } 
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
    my $type = ( $gmode eq 'subtract' ) ? $data->{stype} : $data->{type};
    my $gdata = ( $gmode eq 'subtract' ) ? 'sub' : 'num';
    my $llimit = ( $gmode eq 'subtract' ) ? $data->{sllimit} : $data->{llimit};
    my $ulimit = ( $gmode eq 'subtract' ) ? $data->{sulimit} : $data->{ulimit};
    my $file = $self->path($data);
    push @args, 
        sprintf('DEF:%s%dt=%s:%s:AVERAGE', $gdata, $i, $file, $gdata),
        sprintf('CDEF:%s%d=%s%dt,%s,%s,LIMIT', $gdata, $i, $gdata, $i, $llimit, $ulimit),
        sprintf('%s:%s%d%s:%s ', $type, $gdata, $i, $data->{color}, $data->{graph_name}),
        sprintf('GPRINT:%s%d:LAST:Cur\: %%4.1lf', $gdata, $i),
        sprintf('GPRINT:%s%d:AVERAGE:Ave\: %%4.1lf', $gdata, $i),
        sprintf('GPRINT:%s%d:MAX:Max\: %%4.1lf', $gdata, $i),
        sprintf('GPRINT:%s%d:MIN:Min\: %%4.1lf\l', $gdata, $i);
    $i++;


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


