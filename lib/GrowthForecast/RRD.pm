package GrowthForecast::RRD;

use strict;
use warnings;
use utf8;
use RRDs;
use HTTP::Date;
use File::Temp;
use File::Zglob;
use File::Path qw//;
use Log::Minimal;
$Log::Minimal::AUTODUMP =1;

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

sub path_short {
    my $self = shift;
    my $data = shift;
    my $file = $self->{root_dir} . '/data/' . $data->{md5} . '_s.rrd';
    if ( ! -f $file ) {
        eval {
            RRDs::create(
                $file,
                '--step', '60',
                'DS:num:GAUGE:120:U:U',
                'DS:sub:GAUGE:120:U:U', 
                'RRA:AVERAGE:0.5:1:4800',  #1分, 3日(80時間)
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

sub update_short {
    my $self = shift;
    my $data = shift;

    my $file = $self->path_short($data);
    eval {
        RRDs::update(
            $file,
            '-t', 'num:sub',
            '--', join(':','N',$data->{number},$data->{subtract_short}),
        );
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    die "udpate rrdfile failed: $@" if $@;
}

my @jp_fonts = grep { -f $_ } zglob("/usr/share/fonts/**/sazanami-gothic.ttf");

sub calc_period {
    my $self = shift;
    my ($span, $from, $to) = @_;
    $span ||= 'd';

    my $period_title;
    my $period;
    my $end = 'now';
    my $xgrid;

    if ( $span eq 'c' || $span eq 'sc' ) {
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
        elsif ( $diff < 4 * 24 * 60 * 60 ) {
            $xgrid = 'HOUR:6:DAY:1:HOUR:6:0:%H';
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
    elsif ( $span eq 'h' || $span eq 'sh' ) {
        $period_title = 'Hourly (5min avg)';
        $period_title = 'Hourly (1min avg)' if $span eq 'sh';
        $period = -1 * 60 * 60 * 2;
        $xgrid = 'MINUTE:10:MINUTE:20:MINUTE:10:0:%M';
    }
    elsif ( $span eq 'n' || $span eq 'sn' ) {
        $period_title = 'Half Day (5min avg)';
        $period_title = 'Half Day (1min avg)' if $span eq 'sn';
        $period = -1 * 60 * 60 * 14;
        $xgrid = 'MINUTE:60:MINUTE:120:MINUTE:120:0:%H %M';
    }
    elsif ( $span eq 'w' ) {
        $period_title = 'Weekly (30min avg)';
        $period = -1 * 60 * 60 * 24 * 8;
        $xgrid = 'DAY:1:DAY:1:DAY:1:86400:%a'
    }
    elsif ( $span eq 'm' ) {
        $period_title = 'Monthly (2hour avg)';
        $period = -1 * 60 * 60 * 24 * 35;
        $xgrid = 'DAY:1:WEEK:1:WEEK:1:604800:Week %W'
    }
    elsif ( $span eq 'y' ) {
        $period_title = 'Yearly (1day avg)';
        $period = -1 * 60 * 60 * 24 * 400;
        $xgrid = 'WEEK:1:MONTH:1:MONTH:1:2592000:%b'
    }
    elsif ( $span eq '3d' || $span eq 's3d') {
        $period_title = '3 Days (5min avg)';
        $period_title = '3 Days (1min avg)' if $span eq 's3d';
        $period = -1 * 60 * 60 * 24 * 3;
        $xgrid = 'HOUR:6:DAY:1:HOUR:6:0:%H';
    }
    elsif ( $span eq '8h' || $span eq 's8h' ) {
        $period_title = '8 Hours (5min avg)';
        $period_title = '8 Hours (1min avg)' if $span eq 's8h'; 
        $period = -1 * 8 * 60 * 60;
        $xgrid = 'MINUTE:30:HOUR:1:HOUR:1:0:%H:%M';
    }
    elsif ( $span eq '4h' || $span eq 's4h') {
        $period_title = '4 Hours (5min avg)';
        $period_title = '4 Hours (1min avg)' if $span eq 's4h'; 
        $period = -1 * 4 * 60 * 60;
        $xgrid = 'MINUTE:30:HOUR:1:MINUTE:30:0:%H:%M';
    }
    else {
        $period_title = 'Daily (5min avg)';
        $period_title = 'Daily (1min avg)' if $span eq 'sd';
        $period = -1 * 60 * 60 * 33; # 33 hours
        $xgrid = 'HOUR:1:HOUR:2:HOUR:2:0:%H';
    }

    return ( $period_title, $period, $end, $xgrid);
}


sub graph {
    my $self = shift;
    my $datas = shift;
    my @datas = ref($datas) eq 'ARRAY' ? @$datas : ($datas);
    my $args = shift;
    my ($a_gmode, $span, $from, $to, $width, $height) = map { $args->{$_} } qw/gmode t from to width height/;
    $span ||= 'd';
    $width ||= 390;
    $height ||= 110;

    my ( $period_title, $period, $end, $xgrid ) = $self->calc_period($span, $from, $to);

    if ( @datas == 1 && $a_gmode eq 'subtract' ) { $period_title = "[subtract] $period_title" } 
    my ($tmpfh, $tmpfile) = File::Temp::tempfile(UNLINK => 0, SUFFIX => ".png");
    my @opt = (
        $tmpfile,
        '-w', $width,
        '-h', $height,
        '-a', 'PNG',
        '-l', 0, #minimum
        '-u', 2, #maximum
        '-x', $args->{xgrid} ? $args->{xgrid} : $xgrid,
        '-s', $period,
        '-e', $end,
        '--slope-mode',
        '--color', 'BACK#'.uc($args->{background_color}),
        '--color', 'CANVAS#'.uc($args->{canvas_color}),
        '--color', 'FONT#'.uc($args->{font_color}),
        '--color', 'FRAME#'.uc($args->{frame_color}),
        '--color', 'AXIS#'.uc($args->{axis_color}),
        '--color', 'SHADEA#'.uc($args->{shadea_color}),
        '--color', 'SHADEB#'.uc($args->{shadeb_color}),
        '--border', $args->{border},
    );

    push @opt, '-y', $args->{ygrid} if $args->{ygrid};
    push @opt, '-t', "$period_title" if !$args->{notitle};
    push @opt, '--no-legend' if !$args->{legend};
    push @opt, '--only-graph' if $args->{graphonly};
    push @opt, '--logarithmic' if $args->{logarithmic};
    push @opt, '--font', "DEFAULT:0:".$jp_fonts[0] if @jp_fonts;
    push @opt, '-u', $args->{upper_limit} if defined $args->{upper_limit};
    push @opt, '-l', $args->{lower_limit} if defined $args->{lower_limit};
    push @opt, '-r' if $args->{rigid};

    my $i=0;
    for my $data ( @datas ) {
        my $gmode = ($data->{c_gmode}) ? $data->{c_gmode} : $a_gmode;
        my $type = ($data->{c_type}) ? $data->{c_type} : ( $gmode eq 'subtract' ) ? $data->{stype} : $data->{type};
        my $gdata = ( $gmode eq 'subtract' ) ? 'sub' : 'num';
        my $llimit = ( $gmode eq 'subtract' ) ? $data->{sllimit} : $data->{llimit};
        my $ulimit = ( $gmode eq 'subtract' ) ? $data->{sulimit} : $data->{ulimit};
        my $stack = ( $data->{stack} && $i > 0 ) ? ':STACK' : '';
        my $file = $span =~ m!^s! ? $self->path_short($data) : $self->path($data);
        push @opt, 
            sprintf('DEF:%s%dt=%s:%s:AVERAGE', $gdata, $i, $file, $gdata),
            sprintf('CDEF:%s%d=%s%dt,%s,%s,LIMIT,%d,%s', $gdata, $i, $gdata, $i, $llimit, $ulimit, $data->{adjustval}, $data->{adjust}),
            sprintf('%s:%s%d%s:%s %s', $type, $gdata, $i, $data->{color}, $data->{graph_name},$stack),
            sprintf('GPRINT:%s%d:LAST:Cur\: %%4.1lf%%s%s', $gdata, $i, $data->{unit}),
            sprintf('GPRINT:%s%d:AVERAGE:Avg\: %%4.1lf%%s%s', $gdata, $i, $data->{unit}),
            sprintf('GPRINT:%s%d:MAX:Max\: %%4.1lf%%s%s', $gdata, $i, $data->{unit}),
            sprintf('GPRINT:%s%d:MIN:Min\: %%4.1lf%%s%s\l', $gdata, $i, $data->{unit}),
            sprintf('VDEF:%s%dcur=%s%d,LAST', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dcur:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%davg=%s%d,AVERAGE', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%davg:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%dmax=%s%d,MAXIMUM', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dmax:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%dmin=%s%d,MINIMUM', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dmin:%%.8lf',$gdata, $i);
        $i++;
    }

    my @graphv;
    eval {
        @graphv = RRDs::graph(map { Encode::encode_utf8($_) } @opt);
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    if ( $@ ) {
        unlink($tmpfile);
        die "draw graph failed: $@";
    }

    $i=0;
    my %graph_args;
    for my $data ( @datas ) {
        my ($current,$average,$max,$min) = (
            $graphv[0]->[$i],
            $graphv[0]->[$i+1],
            $graphv[0]->[$i+2],
            $graphv[0]->[$i+3]
        );
        $graph_args{$data->{graph_name}} = [$current, $average, $max, $min];
        $i = $i + 4;
    }

    open( my $fh, '<:bytes', $tmpfile ) or die "cannot open graph tmpfile: $!";
    local $/;
    my $graph_img = <$fh>;
    unlink($tmpfile);

    die 'something wrong with image' unless $graph_img;

    return ($graph_img,\%graph_args);
}

sub export {
    my $self = shift;
    my $datas = shift;
    my @datas = ref($datas) eq 'ARRAY' ? @$datas : ($datas);
    my $args = shift;
    my ($a_gmode, $span, $from, $to, $width) = map { $args->{$_} } qw/gmode t from to width/;
    $span ||= 'd';
    $width ||= 390;

    my ( $period_title, $period, $end, $xgrid ) = $self->calc_period($span, $from, $to);

    my @opt = (
        '-m', $width,
        '-s', $period,
        '-e', $end,
    );

    my $i=0;
    for my $data ( @datas ) {
        my $gmode = ($data->{c_gmode}) ? $data->{c_gmode} : $a_gmode;
        my $type = ($data->{c_type}) ? $data->{c_type} : ( $gmode eq 'subtract' ) ? $data->{stype} : $data->{type};
        my $gdata = ( $gmode eq 'subtract' ) ? 'sub' : 'num';
        my $llimit = ( $gmode eq 'subtract' ) ? $data->{sllimit} : $data->{llimit};
        my $ulimit = ( $gmode eq 'subtract' ) ? $data->{sulimit} : $data->{ulimit};
        my $stack = ( $data->{stack} && $i > 0 ) ? ':STACK' : '';
        my $file = $span =~ m!^s! ? $self->path_short($data) : $self->path($data);
        push @opt, 
            sprintf('DEF:%s%dt=%s:%s:AVERAGE', $gdata, $i, $file, $gdata),
            sprintf('CDEF:%s%d=%s%dt,%s,%s,LIMIT,%d,%s', $gdata, $i, $gdata, $i, $llimit, $ulimit, $data->{adjustval}, $data->{adjust}),
            sprintf('XPORT:%s%d:%s', $gdata, $i ,$data->{graph_name});
        $i++;
    }
    my %export;
    eval {
        my ($start_timestamp, $end_timestamp, $step, $columns, $column_names, $rows) = RRDs::xport(map { Encode::encode_utf8($_) } @opt);
        my $ERR=RRDs::error;
        die $ERR if $ERR;
        $export{start_timestamp} = $start_timestamp;
        $export{end_timestamp} = $end_timestamp;
        $export{step} = $step;
        $export{columns} = $columns;
        $export{column_names} = $column_names;
        $export{rows} = $rows;
    };
    if ( $@ ) {
        die "export failed: $@";
    }

    return \%export;
}


sub remove {
    my $self = shift;
    my $data = shift;
    my $file = $self->{root_dir} . '/data/' . $data->{md5} . '.rrd';
    File::Path::rmtree($file);
}

1;


