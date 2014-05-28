package GrowthForecast::RRD;

use strict;
use warnings;
use utf8;
use RRDs 1.4004;
use HTTP::Date;
use File::Temp;
use File::Zglob;
use File::Path qw//;
use Log::Minimal;
$Log::Minimal::AUTODUMP =1;

sub new {
    my $class = shift;
    my %args = @_;
    bless \%args, $class;
}

sub path_param {
    my $self = shift;
    my $data = shift;

    my $dst = $data->{mode} eq 'derive' ? 'DERIVE' : 'GAUGE';
    my $timestamp = $data->{timestamp} || time;

    my @param = (
        '--start', $timestamp - 10, # -10 as rrdcreate's default does (now - 10s)
        '--step', '300',
        "DS:num:${dst}:600:U:U",
        'RRA:AVERAGE:0.5:1:1440',  #5分, 5日
        'RRA:AVERAGE:0.5:6:1008', #30分, 21日
        'RRA:AVERAGE:0.5:24:1344', #2時間, 112日 
        'RRA:AVERAGE:0.5:288:2500', #24時間, 500日
        'RRA:MAX:0.5:1:1440',  #5分, 5日
        'RRA:MAX:0.5:6:1008', #30分, 21日
        'RRA:MAX:0.5:24:1344', #2時間, 112日 
        'RRA:MAX:0.5:288:2500', #24時間, 500日
    );
    unless ( $self->{disable_subtract} ) {
        # --disable-subtract does not create DS:sub which results in half disksize and half rrdupdate time
        push(@param, "DS:sub:${dst}:600:U:U");
    }
    return @param;
}

sub path {
    my $self = shift;
    my $data = shift;

    my $file = $self->{data_dir} . '/' . $data->{md5} . '.rrd';
    if ( ! -f $file ) {
        eval {
            my @param = $self->path_param($data);
            RRDs::create($file, @param);
            my $ERR=RRDs::error;
            die $ERR if $ERR;
        };
        die "init failed: $@" if $@;
    }
    $file;
}

sub path_short_param {
    my $self = shift;
    my $data = shift;

    my $dst = $data->{mode} eq 'derive' ? 'DERIVE' : 'GAUGE';
    my $timestamp = $data->{timestamp} || time;

    my @param = (
        '--start', $timestamp - 10, # -10 as rrdcreate's default does (now - 10s)
        '--step', '60',
        "DS:num:${dst}:120:U:U",
        'RRA:AVERAGE:0.5:1:4800',  #1分, 3日(80時間)
        'RRA:MAX:0.5:1:4800',  #1分, 3日(80時間)
    );
    unless ( $self->{disable_subtract} ) {
        # --disable-subtract does not create DS:sub which results in half disksize and half rrdupdate time
        push(@param, "DS:sub:${dst}:120:U:U");
    }
    return @param;
}

sub path_short {
    my $self = shift;
    my $data = shift;

    my $file = $self->{data_dir} . '/' . $data->{md5} . '_s.rrd';
    if ( ! -f $file ) {
        eval {
            my @param = $self->path_short_param($data);
            RRDs::create($file, @param);
            my $ERR=RRDs::error;
            die $ERR if $ERR;
        };
        die "init failed: $@" if $@;
    }
    $file;
}

sub update_param {
    my $self = shift;
    my $data = shift;

    my @param;
    my $timestamp = $data->{timestamp} || 'N';
    if ( $self->{disable_subtract} ) {
        @param = (
            '-t', 'num',
            '--', join(':',$timestamp,$data->{number}),
        );
    }
    else {
        @param = (
            '-t', 'num:sub',
            '--', join(':',$timestamp,$data->{number},$data->{subtract}),
        );
    }
    if ( $self->{rrdcached} ) {
        # The caching daemon cannot be used together with templates (-t) yet.
        splice(@param, 0, 2); # delete -t option
        unshift(@param, '-d', $self->{rrdcached});
    }
    return @param;
}

sub update {
    my $self = shift;
    my $data = shift;

    my $file = $self->path($data);
    eval {
        my @param = $self->update_param($data);
        RRDs::update($file, @param);
        my $ERR=RRDs::error;
        if ( $ERR ) {
            if ( $ERR =~ /illegal attempt to update using time.*when last update time is.*minimum one second step/ ) {
                debugf "update rrdfile failed: $ERR";
            }
            else {
                die $ERR;
            }
        }
    };
    die "udpate rrdfile failed: $@" if $@;
}

sub update_short_param {
    my $self = shift;
    my $data = shift;

    my @param;
    my $timestamp = $data->{timestamp} || 'N';
    if ( $self->{disable_subtract} ) {
        @param = (
            '-t', 'num',
            '--', join(':',$timestamp,$data->{number}),
        );
    }
    else {
        @param = (
            '-t', 'num:sub',
            '--', join(':',$timestamp,$data->{number},$data->{subtract_short}),
        );
    }
    if ( $self->{rrdcached} ) {
        # The caching daemon cannot be used together with templates (-t) yet.
        splice(@param, 0, 2); # delete -t option
        unshift(@param, '-d', $self->{rrdcached});
    }
    return @param;
}

sub update_short {
    my $self = shift;
    my $data = shift;

    my $file = $self->path_short($data);
    eval {
        my @param = $self->update_short_param($data);
        RRDs::update($file, @param);
        my $ERR=RRDs::error;
        if ( $ERR ) {
            if ( $ERR =~ /illegal attempt to update using time.*when last update time is.*minimum one second step/ ) {
                debugf "update rrdfile failed: $ERR";
            }
            else {
                die $ERR;
            }
        }
    };
    die "udpate rrdfile failed: $@" if $@;
}

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
        $period_title = 'Hour (5min avg)';
        $period_title = 'Hour (1min avg)' if $span eq 'sh';
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
        $period_title = 'Week (30min avg)';
        $period = -1 * 60 * 60 * 24 * 8;
        $xgrid = 'DAY:1:DAY:1:DAY:1:86400:%a'
    }
    elsif ( $span eq 'm' ) {
        $period_title = 'Month (2hour avg)';
        $period = -1 * 60 * 60 * 24 * 35;
        $xgrid = 'DAY:1:WEEK:1:WEEK:1:604800:Week %W'
    }
    elsif ( $span eq 'y' ) {
        $period_title = 'Year (1day avg)';
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
        $period_title = 'Day (5min avg)';
        $period_title = 'Day (1min avg)' if $span eq 'sd';
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
        '--disable-rrdtool-tag',
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
    push @opt, '--font', "AXIS:8:";
    push @opt, '--font', "LEGEND:8:";
    push @opt, '-u', $args->{upper_limit} if defined $args->{upper_limit};
    push @opt, '-l', $args->{lower_limit} if defined $args->{lower_limit};
    push @opt, '-r' if $args->{rigid};

    my $i=0;
    my @defs;
    for my $data ( @datas ) {
        my $gmode = ($data->{c_gmode}) ? $data->{c_gmode} : $a_gmode;
        my $type = ($data->{c_type}) ? $data->{c_type} : ( $gmode eq 'subtract' ) ? $data->{stype} : $data->{type};
        my $gdata = ( $gmode eq 'subtract' ) ? 'sub' : 'num';
        my $llimit = ( $gmode eq 'subtract' ) ? $data->{sllimit} : $data->{llimit};
        my $ulimit = ( $gmode eq 'subtract' ) ? $data->{sulimit} : $data->{ulimit};
        my $stack = ( $data->{stack} && $i > 0 ) ? ':STACK' : '';
        my $file = $span =~ m!^s! ? $self->path_short($data) : $self->path($data);
        my $unit = $data->{unit};
        $unit =~ s!%!%%!;
        push @opt, 
            sprintf('DEF:%s%dt=%s:%s:AVERAGE', $gdata, $i, $file, $gdata),
            sprintf('CDEF:%s%d=%s%dt,%s,%s,LIMIT,%d,%s', $gdata, $i, $gdata, $i, $llimit, $ulimit, $data->{adjustval}, $data->{adjust}),
            sprintf('%s:%s%d%s:%s %s', $type, $gdata, $i, $data->{color}, $self->_escape($data->{graph_name}), $stack),
            sprintf('GPRINT:%s%d:LAST:Cur\: %%4.1lf%%s%s', $gdata, $i, $unit),
            sprintf('GPRINT:%s%d:AVERAGE:Avg\: %%4.1lf%%s%s', $gdata, $i, $unit),
            sprintf('GPRINT:%s%d:MAX:Max\: %%4.1lf%%s%s', $gdata, $i, $unit),
            sprintf('GPRINT:%s%d:MIN:Min\: %%4.1lf%%s%s\l', $gdata, $i, $unit),
            sprintf('VDEF:%s%dcur=%s%d,LAST', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dcur:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%davg=%s%d,AVERAGE', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%davg:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%dmax=%s%d,MAXIMUM', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dmax:%%.8lf',$gdata, $i),
            sprintf('VDEF:%s%dmin=%s%d,MINIMUM', $gdata, $i, $gdata, $i),
            sprintf('PRINT:%s%dmin:%%.8lf',$gdata, $i);
        push @defs, sprintf('%s%d',$gdata, $i);
        $i++;
    }
    if ( $args->{sumup} ) {
        my @sumup = (shift @defs);
        my $unit = $datas[0]->{unit};
        $unit =~ s!%!%%!;
        push @sumup, $_, '+' for @defs;
        push @opt, 
            sprintf('CDEF:sumup=%s',join(',',@sumup)),
            sprintf('LINE0:sumup#cccccc:total'),
            sprintf('GPRINT:sumup:LAST:Cur\: %%4.1lf%%s%s', $unit),
            sprintf('GPRINT:sumup:AVERAGE:Avg\: %%4.1lf%%s%s', $unit),
            sprintf('GPRINT:sumup:MAX:Max\: %%4.1lf%%s%s', $unit),
            sprintf('GPRINT:sumup:MIN:Min\: %%4.1lf%%s%s\l', $unit),
            sprintf('VDEF:sumupcur=sumup,LAST'),
            sprintf('PRINT:sumupcur:%%.8lf'),
            sprintf('VDEF:sumupavg=sumup,AVERAGE'),
            sprintf('PRINT:sumupavg:%%.8lf'),
            sprintf('VDEF:sumupmax=sumup,MAXIMUM'),
            sprintf('PRINT:sumupmax:%%.8lf'),
            sprintf('VDEF:sumupmin=sumup,MINIMUM'),
            sprintf('PRINT:sumupmin:%%.8lf');
    }

    my %same_vrule;
    for my $vrule ($self->{data}->get_vrule($span, $period, $end, '/'.join('/',@{$datas[0]}{qw(service_name section_name graph_name)}))) {
        my $desc = "";
        if ($vrule->{description}) {
            my $k = $vrule->{color}.'/'.$vrule->{description};
            unless ($same_vrule{$k}) {
                $desc = $vrule->{description};
                $desc =~ s/:/\\:/;
            }
            $same_vrule{$k}++;
        }

        push @opt, join(":",
                        'VRULE',
                        join("", $vrule->{time}, $vrule->{color}),
                        ($args->{vrule_legend} ? $desc : ""),
                        ($vrule->{dashes} ? 'dashes='.$vrule->{dashes} : ()),
                    );
    }
    push @opt, 'COMMENT:\n';

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
        my $graph_path = join('/', $data->{service_name}, $data->{section_name}, $data->{graph_name});
        $graph_args{$graph_path} = [$current, $average, $max, $min];
        $i = $i + 4;
    }
    if ( $args->{sumup} ) {
        my ($current,$average,$max,$min) = (
            $graphv[0]->[$i],
            $graphv[0]->[$i+1],
            $graphv[0]->[$i+2],
            $graphv[0]->[$i+3]
        );
        $graph_args{'total'} = [$current, $average, $max, $min];
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
    my ($a_gmode, $span, $from, $to, $width, $cf) = map { $args->{$_} } qw/gmode t from to width cf/;
    $span ||= 'd';
    $width ||= 390;

    my ( $period_title, $period, $end, $xgrid ) = $self->calc_period($span, $from, $to);

    my @opt = (
        '-m', $width,
        '-s', $period,
        '-e', $end,
    );

    push @opt, '--step', $args->{step} if $args->{step};

    my $i=0;
    my @defs;
    for my $data ( @datas ) {
        my $gmode = ($data->{c_gmode}) ? $data->{c_gmode} : $a_gmode;
        my $type = ($data->{c_type}) ? $data->{c_type} : ( $gmode eq 'subtract' ) ? $data->{stype} : $data->{type};
        my $gdata = ( $gmode eq 'subtract' ) ? 'sub' : 'num';
        my $llimit = ( $gmode eq 'subtract' ) ? $data->{sllimit} : $data->{llimit};
        my $ulimit = ( $gmode eq 'subtract' ) ? $data->{sulimit} : $data->{ulimit};
        my $stack = ( $data->{stack} && $i > 0 ) ? ':STACK' : '';
        my $file = $span =~ m!^s! ? $self->path_short($data) : $self->path($data);
        push @opt, 
            sprintf('DEF:%s%dt=%s:%s:%s', $gdata, $i, $file, $gdata, $cf),
            sprintf('CDEF:%s%d=%s%dt,%s,%s,LIMIT,%d,%s', $gdata, $i, $gdata, $i, $llimit, $ulimit, $data->{adjustval}, $data->{adjust}),
            sprintf('XPORT:%s%d:%s', $gdata, $i ,$self->_escape($data->{graph_name}));
        push @defs, sprintf('%s%d',$gdata,$i);
        $i++;
    }
    if ( $args->{sumup} ) {
        my @sumup = (shift @defs);
        push @sumup, $_, '+' for @defs;
        push @opt, 
            sprintf('CDEF:sumup=%s',join(',',@sumup)),
            sprintf('XPORT:sumup:total');
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
    my $file;
    $file = $self->{data_dir} . '/' . $data->{md5} . '.rrd';
    File::Path::rmtree($file);
    $file = $self->{data_dir} . '/' . $data->{md5} . '_s.rrd';
    File::Path::rmtree($file);
}

sub _escape {
    my $self = shift;
    my $data = shift;
    $data =~ s{:}{\\:}g;
    return $data;
}

1;


