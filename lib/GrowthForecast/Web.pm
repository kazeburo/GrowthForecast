package GrowthForecast::Web;

use strict;
use warnings;
use utf8;
use Kossy 0.10;
use JSON;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;
use Log::Minimal;
use Class::Accessor::Lite ( rw => [qw/short mysql data_dir float_number rrdcached disable_subtract/] );
use CGI;

sub data {
    my $self = shift;
    $self->{__data} ||= 
        $self->mysql 
            ? GrowthForecast::Data::MySQL->new($self->mysql, $self->float_number, $self->disable_subtract)
            : GrowthForecast::Data->new($self->data_dir, $self->float_number, $self->disable_subtract);
    $self->{__data};
}

sub number_type {
    my $self = shift;
    return $self->{'float_number'} ? 'REAL' : 'INT';
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new(
        data_dir => $self->data_dir,
        root_dir => $self->root_dir,
        rrdcached => $self->rrdcached,
        disable_subtract => $self->disable_subtract,
        data => $self->data,
    );
    $self->{__rrd};
}

sub gmode_choice {
    my ($self) = @_;
    return $self->disable_subtract ? qw/gauge/ : qw/gauge subtract/;
}

sub gmode_choice_edit_graph {
    my ($self) = @_;
    return $self->disable_subtract ? qw/gauge/ : qw/gauge subtract both/;
}

filter 'set_enable_short' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        $c->stash->{enable_short} = $self->short;
        $app->($self,$c);
    }
};

filter 'get_graph' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        my $row = $self->data->get(
            $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
        );
        $c->halt(404) unless $row;
        $c->stash->{graph} = $row;
        $app->($self,$c);
    }
};


filter 'get_complex' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        my $row = $self->data->get_complex_by_id(
            $c->args->{complex_id}
        );
        $c->halt(404) unless $row;
        $c->stash->{complex} = $row;
        $app->($self,$c);
    }
};

sub delete_graph {
    my ( $self, $c ) = @_;
    $self->data->remove($c->stash->{graph}->{id});
    $self->rrd->remove($c->stash->{graph});

    $c->render_json({
        error => 0,
        location => "".$c->req->uri_for(sprintf('/list/%s/%s', map { CGI::escape($c->stash->{graph}->{$_}) } qw/service_name section_name/))
    });
};

sub delete_complex {
    my ( $self, $c ) = @_;
    $self->data->remove_complex($c->stash->{complex}->{id});

    $c->render_json({
        error => 0,
        location => "". $c->req->uri_for(sprintf('/list/%s/%s', map { CGI::escape($c->stash->{complex}->{$_}) } qw/service_name section_name/))
    });
};

get '/' => sub {
    my ( $self, $c )  = @_;
    my $services = $self->data->get_services();
    my @services;
    for my $service ( @$services ) {
        my $sections = $self->data->get_sections($service);
        push @services , {
            name => $service,
            sections => $sections,
        };
    }
    $c->render('index.tx', { services => \@services });
};


get '/docs' => sub {
    my ( $self, $c )  = @_;
    $c->stash->{docs} = 1;
    $c->render('docs.tx',{});
};

get '/add_complex' => sub {
    my ( $self, $c )  = @_;
    my $graphs = $self->data->get_all_graph_name();
    $c->render('add_complex.tx',{ graphs => $graphs, disable_subtract => $self->disable_subtract });
};

get '/edit_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    my $graphs = $self->data->get_all_graph_name();
    $c->render('edit_complex.tx',{ graphs => $graphs, disable_subtract => $self->disable_subtract });
};

post '/delete_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    $self->delete_complex( $c );
};

sub check_uniq_complex {
    my ($self,$id) = @_;
    sub {
        my ($req,$val) = @_;
        my $service = $req->param('service_name');
        my $section = $req->param('section_name');
        my $graph = $req->param('graph_name');
        $service = '' if !defined $service;
        $section = '' if !defined $section;
        $graph = '' if !defined $graph;
        my $row = $self->data->get_complex($service,$section,$graph);
        if ($id) {
            return 1 if $row && $row->{id} == $id;
        }
        return 1 if !$row;
        return;
    };
}

post '/add_complex' => sub {
    my ( $self, $c )  = @_;
    my @type2 = $c->req->param('type-2');
    my $type2_num = scalar @type2;
    $type2_num = 1 if !$type2_num;
    my @gmode_choice = $self->gmode_choice;
    my $result = $c->req->validator([
        'service_name' => {
            rule => [
                ['NOT_NULL', '"server name" is missing'],
            ],
        },
        'section_name' => {
            rule => [
                ['NOT_NULL', '"section name" is missing'],
            ],
        },
        'graph_name' => {
            rule => [
                ['NOT_NULL', '"graph name" is missing'],
                [$self->check_uniq_complex,'This graph name is already existing'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'sumup' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',0,1], 'invalid value'],
            ],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',0..19], 'invalid value'],
            ],
        },
        'type-1' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid value'],
            ],
        },
        'path-1' => {
            rule => [
                ['NOT_NULL', 'missing'],
                ['NATURAL', 'invalid value'],
            ],
        },
        'gmode-1' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',@gmode_choice], 'invalid value'],
            ],
        },
        '@type-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid type'],
                ['NOT_NULL','invalid type'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid type'],
            ],
        },
        '@path-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid path'],
                ['NOT_NULL','invalid path'],
                ['NATURAL', 'invalid path'],
            ],
        },
        '@gmode-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid mode'],
                ['NOT_NULL', 'invalid mode'],
                [['CHOICE',@gmode_choice], 'invalid mode'],
            ],
        },
        '@stack-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid stack flag'],
                ['NOT_NULL', 'invalid stack flag'],
                [['CHOICE',qw/0 1/], 'invalid stack flag'],
            ],
        },
    ]);
    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->errors
        });
        return $res;
    }

    $self->data->create_complex(
        $result->valid('service_name'),$result->valid('section_name'),$result->valid('graph_name'),
        $result->valid->mixed
    );

    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/list/'.CGI::escape($result->valid('service_name')).'/'.CGI::escape($result->valid('section_name')))->as_string,
    });
};


post '/edit_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    my @type2 = $c->req->param('type-2');
    my $type2_num = scalar @type2;
    $type2_num = 1 if !$type2_num;
    my @gmode_choice = $self->gmode_choice;
    my $result = $c->req->validator([
        'service_name' => {
            rule => [
                ['NOT_NULL', 'service_name is missing'],
            ],
        },
        'section_name' => {
            rule => [
                ['NOT_NULL', 'section_name is missing'],
            ],
        },
        'graph_name' => {
            rule => [
                ['NOT_NULL', 'graph_name is missing'],
                [$self->check_uniq_complex($c->stash->{complex}->{id}),'this graph_name is already exists'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'sumup' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',0,1], 'invalid value'],
            ],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',0..19], 'invalid value'],
            ],
        },
        'type-1' => {
            rule => [
                ['NOT_NULL', 'type is missing'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid type'],
            ],
        },
        'path-1' => {
            rule => [
                ['NOT_NULL', 'path is missing'],
                ['NATURAL', 'invalid path'],
            ],
        },
        'gmode-1' => {
            rule => [
                ['NOT_NULL', 'mode is missing'],
                [['CHOICE',@gmode_choice], 'invalid mode'],
            ],
        },
        '@type-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid type'],
                ['NOT_NULL','invalid type'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid type'],
            ],
        },
        '@path-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid path'],
                ['NOT_NULL','invalid path'],
                ['NATURAL', 'invalid path'],
            ],
        },
        '@gmode-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid mode'],
                ['NOT_NULL', 'invalid mode'],
                [['CHOICE',@gmode_choice], 'invalid mode'],
            ],
        },
        '@stack-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'invalid stack flag'],
                ['NOT_NULL', 'invalid stack flag'],
                [['CHOICE',qw/0 1/], 'invalid stack flag'],
            ],
        },
    ]);
    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->errors
        });
        return $res;
    }
    $self->data->update_complex(
        $c->stash->{complex}->{id},
        $result->valid->mixed
    );

    $c->render_json({
        error => 0,
        location => $c->req->uri_for( sprintf '/view_complex/%s/%s/%s', CGI::escape($result->valid('service_name')), CGI::escape($result->valid('section_name')), CGI::escape($result->valid('graph_name')) )->as_string,
    });
};

get '/list/:service_name' => sub {
    my ( $self, $c )  = @_;
    my $services = $self->data->get_services();
    my @services;
    my $sections = $self->data->get_sections($c->args->{service_name});
    push @services , {
        name => $c->args->{service_name},
        sections => $sections,
    };
    $c->render('index.tx', { services => \@services });
};

get '/list/:service_name/:section_name' => [qw/set_enable_short/] => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        't' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/h m sh sd/],'invalid browse term'],
            ],
        },
    ]);
    my $rows = $self->data->get_graphs(
        $c->args->{service_name}, $c->args->{section_name}
    );
    $c->render('list.tx',{ graphs => $rows });
};

get '/view_graph/:service_name/:section_name/:graph_name' => [qw/get_graph set_enable_short/] => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        't' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/h m sh sd/],'invalid browse term'],
            ],
        },
    ]);
    $c->render('view_graph.tx',{ graphs => [$c->stash->{graph}] });
};

get '/view_complex/:service_name/:section_name/:graph_name' => [qw/set_enable_short/] => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        't' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/h m sh sd/],'invalid browse term'],
            ],
        },
    ]);
    my $row = $self->data->get_complex(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
    );
    $c->halt(404) unless $row;
    $c->render('view_graph.tx',{ graphs => [$row], view_complex => 1 } );
};

sub graph_validator {
    my ( $self ) = @_;
    my @gmode_choice = $self->gmode_choice;

    return [
        't' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/y m w 3d s3d d sd 8h s8h 4h s4h h sh n sn c sc/],'invalid drawing term'],
            ],
        },
        'gmode' => {
            default => 'gauge',
            rule => [
                [['CHOICE',@gmode_choice],'invalid drawing data'],
            ],
        },
        'from' => {
            default => localtime(time-86400*8)->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid From datetime'],
            ],
        },
        'to' => {
            default => localtime()->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid To datetime'],
            ],
        },
        'width' => {
            default => 390,
            rule => [
                ['NATURAL','invalid width'],
            ],
        },
        'height' => {
            default => 110,
            rule => [
                ['NATURAL','invalid height'],
            ],
        },
        'graphonly' => {
            default => 0,
            rule => [
                [['CHOICE',qw/0 1/],'invalid only flag'],
            ],
        },
        'logarithmic' => {
            default => 0,
            rule => [
                [['CHOICE',qw/0 1/],'invalid logarithmic flag'],
            ],
        },
        'background_color' => {
            default => 'f3f3f3',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid background color'],
            ],
        },
        'canvas_color' => {
            default => 'ffffff',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid canvas color'],
            ],
        },
        'font_color' => {
            default => '000000',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid font color'],
            ],
        },
        'frame_color' => {
            default => '000000',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid frame color'],
            ],
        },
        'axis_color' => {
            default => '000000',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid axis color'],
            ],
        },
        'shadea_color' => {
            default => 'cfcfcf',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid shadea color'],
            ],
        },
        'shadeb_color' => {
            default => '9e9e9e',
            rule => [
                [sub{ $_[1] =~ m!^[0-9A-F]{6}$!i || $_[1] =~ m!^[0-9A-F]{8}$!i }, 'invalid shadeb color'],
            ],
        },
        'border' => {
            default => 3,
            rule => [
                ['UINT','invalid border width'],
            ],
        },
        'legend' => {
            default => 1,
            rule => [
                [['CHOICE',qw/0 1/],'invalid legend flag'],
            ],
        },
        'notitle' => {
            default => 0,
            rule => [
                [['CHOICE',qw/0 1/],'invalid title flag'],
            ],
        },
        'xgrid' => {
            default => '',
            rule => [],
        },
        'ygrid' => {
            default => '',
            rule => [],
        },
        'upper_limit' => {
            default => '',
            rule => [],
        },
        'lower_limit' => {
            default => '',
            rule => [],
        },
        'rigid' => {
            default => '0',
            rule => [
                [['CHOICE',qw/0 1/],'invalid rigid flag'],
            ],
        },
        'sumup' => {
            default => 0,
            rule => [
                [['CHOICE',qw/0 1/],'invalid sumup flag'],
            ],
        },
        'step' => {
            default => '',
            rule => [
                ['NATURAL', 'invalid step size'],
            ],
        },
        'cf' => {
            default => 'AVERAGE',
            rule => [
                [['CHOICE', qw/AVERAGE MAX/], 'invalid consolidation function'],
            ],
        },
        'vrule_legend' => {
            default => 1,
            rule => [
                [['CHOICE',qw/0 1/],'invalid vrule_legend flag'],
            ],
        },
    ];
}

get '/complex/{method:(?:xport|graph|summary)}/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator($self->graph_validator);
    my $complex = $self->data->get_complex(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
    );
    $c->halt(404) unless $complex;

    my @data;
    $data[0] = $self->data->get_by_id($complex->{'path-1'});
    $data[0]->{c_type} = $complex->{'type-1'};
    $data[0]->{c_gmode} = $complex->{'gmode-1'};
    $data[0]->{stack} = 0;

    for my $row (@{$complex->{data_rows}}){
      my $data = $row->{graph};
      $data->{c_type} = $row->{type};
      $data->{c_gmode} = $row->{gmode};
      $data->{stack} = $row->{stack};
      push @data, $data;
    }

    if ( $c->args->{method} eq 'graph' ) {
        my ($img,$data) = $self->rrd->graph(
            \@data, $result->valid->as_hashref
        );
        $c->res->content_type('image/png');
        $c->res->body($img);
    }
    elsif ( $c->args->{method} eq 'summary' ) {
        my ($img,$data) = $self->rrd->graph(
            \@data, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    else {
        my $data = $self->rrd->export(
            \@data, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    return $c->res;
};

get '/{method:(?:xport|graph|summary)}/:complex' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator($self->graph_validator);
    my @complex = split /:/, $c->args->{complex};
    my @data;
    for ( my $i=0; $i < @complex; $i = $i+4 ) {
        my $type = $complex[$i];
        my $id = $complex[$i+1];
        my $gmode = $complex[$i+2];
        my $stack = $complex[$i+3];
        my $data = $self->data->get_by_id($id);
        next unless $data;
        $data->{c_type} = $type;
        $data->{c_gmode} = $gmode;
        $data->{stack} = $stack;
        push @data, $data;
    }
    if ( $c->args->{method} eq 'graph' ) {
        my ($img,$data) = $self->rrd->graph(
            \@data, $result->valid->as_hashref
        );
        $c->res->content_type('image/png');
        $c->res->body($img);
    }
    elsif ( $c->args->{method} eq 'summary' ) {
        my ($img,$data) = $self->rrd->graph(
            \@data, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    else {
        my $data = $self->rrd->export(
            \@data, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    return $c->res;
};


get '/{method:(?:xport|graph|summary)}/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator($self->graph_validator);

    if ( $c->args->{method} eq 'graph' ) {
        my ($img,$data) = $self->rrd->graph(
            $c->stash->{graph}, $result->valid->as_hashref,
            $self->data,
        );
        $c->res->content_type('image/png');
        $c->res->body($img);
    }
    elsif ( $c->args->{method} eq 'summary' ) {
        my ($img,$data) = $self->rrd->graph(
            $c->stash->{graph}, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    else {
        my $data = $self->rrd->export(
            $c->stash->{graph}, $result->valid->as_hashref
        );
        $c->render_json($data);
    }
    return $c->res;
};

get '/edit/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $c->render('edit.tx',{graph=>$c->stash->{graph},disable_subtract=>$self->disable_subtract});
};

post '/edit/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    my $check_uniq = sub {
        my ($req,$val) = @_;
        my $service = $req->param('service_name');
        my $section = $req->param('section_name');
        my $graph = $req->param('graph_name');
        $service = '' if !defined $service;
        $section = '' if !defined $section;
        $graph = '' if !defined $graph;
        my $row = $self->data->get($service,$section,$graph);
        return 1 if $row && $row->{id} == $c->stash->{graph}->{id};
        return 1 if !$row;
        return;
    };

    my $result = $c->req->validator([
        'service_name' => {
            rule => [
                ['NOT_NULL', 'service_name is missing'],
            ],
        },
        'section_name' => {
            rule => [
                ['NOT_NULL', 'section_name is missing'],
            ],
        },
        'graph_name' => {
            rule => [
                ['NOT_NULL', 'graph_name is missing'],
                [$check_uniq,'This graph_name is already existing'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',0..19], 'invalid value'],
            ],
        },
        'gmode' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',$self->gmode_choice_edit_graph], 'invalid value'],
            ],
        },
        'adjust' => {
            default => '*',
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE','*','/'], 'invalid value'],
            ]
        },
        'adjustval' => {
            default => '1',
            rule => [
                ['NOT_NULL', 'missing'],
                ['NATURAL', 'a integral number is required'],
            ],
        },
        'unit' => {
            default => '',
            rule => [],
        },
        'color' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [sub{ $_[1] =~ m!^#[0-9A-F]{6}$!i }, 'color supports #000000 format'],
            ],
        },
        'type' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid value'],
            ],
        },
        'stype' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'invalid value'],
            ],
        },
        'llimit' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [$self->number_type, 'a ' . $self->number_type . ' number is required'],
            ],
        },
        'ulimit' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [$self->number_type, 'a ' . $self->number_type . ' number is required'],
            ],
        },
        'sllimit' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [$self->number_type, 'a ' . $self->number_type . ' number is required'],
            ],
        },
        'sulimit' => {
            rule => [
                ['NOT_NULL', 'missing'],
                [$self->number_type, 'a ' . $self->number_type . ' number is required'],
            ],
        },
    ]);
    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->errors
        });
        return $res;
    }

    
    $self->data->update_graph(
        $c->stash->{graph}->{id},
        $result->valid->as_hashref
    );

    $c->render_json({
        error => 0,
        location => $c->req->uri_for( sprintf '/view_graph/%s/%s/%s', CGI::escape($result->valid('service_name')), CGI::escape($result->valid('section_name')), CGI::escape($result->valid('graph_name')) )->as_string
    });
};

post '/delete/:service_name/:section_name' => [qw/set_enable_short/] => sub {
    my ( $self, $c )  = @_;

    my $graphs = $self->data->get_graphs(
        $c->args->{service_name}, $c->args->{section_name}
    );
    for my $g (@$graphs) {
        if ( exists $g->{complex_graph} ) {
            $self->data->remove_complex($g->{id});
        }
        else {
            $self->data->remove($g->{id});
            $self->rrd->remove($g);
        }
    }

    $c->render_json({
        error => 0,
        location => "".$c->req->uri_for(sprintf('/list/%s', CGI::escape($c->args->{service_name})))
    });
};

post '/delete/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $self->delete_graph( $c );
};

get '/api/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $c->render_json($c->stash->{graph});
};

post '/api/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        'number' => {
            rule => [
                ['NOT_NULL','number is missing'],
                [$self->number_type, 'a ' . $self->number_type . ' number is required for "number"']
            ],
        },
        'mode' => {
            default => 'gauge',
            rule => [
                [['CHOICE',qw/count gauge modified derive/],'count or gauge or modified or derive']
            ],
        },
        'color' => {
            default => '',
            rule => [
                [sub{ length($_[1]) == 0 || $_[1] =~ m!^#[0-9A-F]{6,8}$!i }, 'invalid color format'],
            ],
        },
        'timestamp' => {
            default => undef,
            rule => [
                # The timestamp is UNIX epoch time
                # The timestamp of rrdcreate must be larger than 315360000 because of its bug.
                # cf. https://lists.oetiker.ch/pipermail/rrd-users/2008-January.txt
                # 10 is because I subtract 10 from the timestamp for rrdcreate as rrdcreate's default does (now - 10s).
                # cf. http://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html
                [sub{ !defined($_[1]) || ($_[1] =~ m!^\-?[\d]+$! && $_[1] > 315360010) }, '"timestamp" must be a INT number and greater than 315360010"']
            ],
        },
        'datetime' => {
            default => undef,
            rule => [
                [ sub { my $t = HTTP::Date::str2time($_[1]); !defined($_[1]) || (defined($t) && $t > 315360010) }, "invalid datetime format or not later than '1979-12-30 00:00:10 UTC'" ]
            ],
        },
    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $row;
    eval {
        my $timestamp = $result->valid('timestamp') || HTTP::Date::str2time($result->valid('datetime'));
        $row = $self->data->update(
            $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
            $result->valid('number'), $result->valid('mode'), $result->valid('color'),
            $timestamp,
        );
    };
    if ( $@ ) {
        die sprintf "Error:%s %s/%s/%s => %s,%s,%s,%s,%s",
            $@, $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
                $result->valid('number'), $result->valid('mode'), $result->valid('color'),
                $result->valid('timestamp'), $result->valid('datetime');
    }
    
    my @descriptions = $c->req->param('description');
    if ( @descriptions ) {
        $self->data->update_graph_description($row->{id}, $descriptions[-1]);
    }

    $c->render_json({ error => 0, data => $row });
};

# from internal hashref (inflated) expression to JSON friendly expression
sub graph4json {
    my ( $self, $internal ) = @_;

    my $json = +{%$internal};

    delete $json->{meta};
    delete $json->{md5}; # only in basic graph

    my $is_complex = delete $json->{complex_graph};

    unless ($is_complex) {
        $json->{complex} = JSON::false;
        return $json;
    }

    # complex graph
    $json->{complex} = JSON::true;

    delete $json->{data_rows};

    my @data_rows = ();
    push @data_rows, +{
        graph_id => (delete $json->{'path-1'}),
        type => (delete $json->{'type-1'}),
        gmode => (delete $json->{'gmode-1'}),
        stack => JSON::false,
    };
    for (my $i = 0 ; $i < scalar(@{$json->{'path-2'}}) ; $i++) {
        push @data_rows, +{
            graph_id => $json->{'path-2'}->[$i],
            type => $json->{'type-2'}->[$i],
            gmode => $json->{'gmode-2'}->[$i],
            stack => ($json->{'stack-2'}->[$i] ? JSON::true : JSON::false),
        };
    }
    delete $json->{'path-2'};
    delete $json->{'type-2'};
    delete $json->{'gmode-2'};
    delete $json->{'stack-2'};

    $json->{sumup} = ($json->{sumup} ? JSON::true : JSON::false);

    $json->{data} = \@data_rows;

    $json;
}

# from JSON API expression to update(update_complex) parameter expression
sub graph4internal {
    my ( $self, $json ) = @_;

    my $internal = +{%$json};

    my $is_complex = delete $internal->{complex};

    delete $internal->{id};
    delete $internal->{created_at};
    delete $internal->{updated_at};

    return $internal unless $is_complex;

    delete $internal->{number};
    $internal->{sumup} = ($internal->{sumup} ? '1' : '0');

    my $data_rows = delete $internal->{data};
    my $first = shift @$data_rows;
    $internal->{'path-1'} = $first->{graph_id};
    $internal->{'type-1'} = $first->{type};
    $internal->{'gmode-1'} = $first->{gmode};
    # stack is ignored for first data

    $internal->{'path-2'} = [];
    $internal->{'type-2'} = [];
    $internal->{'gmode-2'} = [];
    $internal->{'stack-2'} = [];
    foreach my $graph (@$data_rows) {
        push @{ $internal->{'path-2'} }, $graph->{graph_id};
        push @{ $internal->{'type-2'} }, $graph->{type};
        push @{ $internal->{'gmode-2'} }, $graph->{gmode};
        push @{ $internal->{'stack-2'} }, ($graph->{stack} ? '1' : '0');
    }

    $internal;
}

# alias to /api/:service_name/:section_name/:graph_name
get '/json/graph/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $c->render_json($c->stash->{graph});
};

get '/json/complex/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c ) = @_;
    my $complex = $self->data->get_complex( $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name} );
    $c->halt(404) unless $complex;
    $c->render_json( $self->graph4json( $complex ) );
};

# alias to /delete/:service_name/:section_name/:graph_name
post '/json/delete/graph/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    $self->delete_graph( $c );
};

post '/json/delete/complex/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_;
    my $complex = $self->data->get_complex( $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name} );
    $c->halt(404) unless $complex;
    $c->stash->{complex} = $complex;

    $self->delete_complex( $c );
};

post '/json/delete/graph/:id' => sub {
    my ( $self, $c ) = @_;
    my $graph = $self->data->get_by_id( $c->args->{id} );
    $c->halt(404) unless $graph;
    $c->stash->{graph} = $graph;

    $self->delete_graph( $c );
};

# alias to /delete_complex/:complex_id
post '/json/delete/complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c ) = @_;
    $self->delete_complex( $c );
};

get '/json/graph/:id' => sub {
    my ( $self, $c ) = @_;
    my $graph = $self->data->get_by_id( $c->args->{id} );
    $c->halt(404) unless $graph;
    $c->render_json( $self->graph4json( $graph ) );
};

get '/json/complex/:id' => sub {
    my ( $self, $c ) = @_;
    my $complex = $self->data->get_complex_by_id( $c->args->{id} );
    $c->halt(404) unless $complex;
    $c->render_json( $self->graph4json( $complex ) );
};

get '/json/list/graph' => sub {
    my ( $self, $c ) = @_;
    $c->render_json( $self->data->get_all_graph_name() );
};

get '/json/list/complex' => sub {
    my ( $self, $c ) = @_;
    $c->render_json( $self->data->get_all_complex_graph_name() );
};

get '/json/list/all' => sub {
    my ( $self, $c ) = @_;
    my @list = map { $self->graph4json($_) } @{ $self->data->get_all_graph_all() }, @{ $self->data->get_all_complex_graph_all() };
    $c->render_json( \@list );
};

# TODO in create/edit, validations about json object properties, sub graph id existense, ....

post '/json/create/complex' => sub {
    my ( $self, $c ) = @_;

    my $spec = decode_json($c->req->content || '{}');

    if ( $self->data->get($spec->{service_name}, $spec->{section_name}, $spec->{graph_name})
             or $self->data->get_complex($spec->{service_name}, $spec->{section_name}, $spec->{graph_name}) ) {
        my $res = $c->res;
        $res->status(409);
        $res->body("Invalid target: graph path already exists: $spec->{service_name}/$spec->{section_name}/$spec->{graph_path}");
        return $res;
    }

    unless ( defined $spec->{data} and scalar(@{$spec->{data}}) >= 2 ) {
        my $res = $c->res;
        $res->status(400);
        $res->body('Invalid argument: data (sub graph list (size >= 2)) required');
        return $res;
    }

    $spec->{complex} = 1;

    $spec->{description} = '' unless defined $spec->{description};
    $spec->{sumup} = 0 unless defined $spec->{sumup};
    $spec->{sort} = 19 unless defined $spec->{sort};

    foreach my $d (@{$spec->{data}}) {
        $d->{type} = 'AREA' unless defined $d->{type};
        $d->{gmode} = 'gauge' unless defined $d->{gmode};
        $d->{stack} = '1' unless defined $d->{stack};
    }

    my $internal = $self->graph4internal( $spec );
    $self->data->create_complex(
        $spec->{service_name}, $spec->{section_name}, $spec->{graph_name},
        $internal
    );
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/list/'.CGI::escape($spec->{service_name}).'/'.CGI::escape($spec->{section_name}))->as_string,
    });
};

post '/json/edit/{type:(?:graph|complex)}/:id' => sub {
    my ( $self, $c ) = @_;

    my $graph;
    if ( $c->args->{type} eq 'graph' ) {
        $graph = $self->data->get_by_id( $c->args->{id} );
    } else { # complex
        $graph = $self->data->get_complex_by_id( $c->args->{id} );
    }
    unless ( $graph ) {
        my $res = $c->res;
        $res->status(404);
        return $res;
    }

    my $spec = decode_json($c->req->content || '{}');
    my $id = delete $spec->{id};
    unless ( $id ) { $id = $graph->{id}; }

    foreach my $d (@{$spec->{data}}) {
        $d->{type} = 'AREA' unless defined $d->{type};
        $d->{gmode} = 'gauge' unless defined $d->{gmode};

        $d->{stack} = '1' unless defined $d->{stack};
    }

    my $internal = $self->graph4internal( $spec );
    if ( $c->args->{type} eq 'graph' ) {
        $self->data->update_graph( $id, $internal );
    } else {
        $self->data->update_complex( $id, $internal );
    }
    $c->render_json({ error => 0 });
};

post '/vrule/api/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_; $self->add_vrule($c);
};
post '/vrule/api/:service_name/:section_name' => sub {
    my ( $self, $c )  = @_; $self->add_vrule($c);
};
post '/vrule/api/:service_name' => sub {
    my ( $self, $c )  = @_; $self->add_vrule($c);
};
post '/vrule/api' => sub {
    my ( $self, $c )  = @_; $self->add_vrule($c);
};

sub add_vrule {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        'time' => {
            default => time(),
            rule => [
                [sub {
                     if ($_[1] !~ /\A[1-9][0-9]*\z/) {
                         my $t = HTTP::Date::str2time($_[1])
                             or return;
                         $_[1] = $t;
                     }
                     return 1;
                 }, 'epoch time or date string is required for "time"'],
            ],
        },
        'color' => {
            default => '#FF0000',
            rule => [
                [sub{ length($_[1]) == 0 || $_[1] =~ m!^#[0-9A-F]{6,8}$!i }, 'invalid color format'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'dashes' => {
            default => '',
            rule => [],
        },
    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $row;
    eval {
        my $graph_path = '/'.join('/', $c->args->{service_name}||(), $c->args->{section_name}||(), $c->args->{graph_name}||());
        $row = $self->data->update_vrule(
            $graph_path,
            $result->valid('time'),
            $result->valid('color'),
            $result->valid('description'),
            $result->valid('dashes'),
        );
    };
    if ( $@ ) {
        die sprintf "Error:%s %s/%s/%s => %s,%s",
            $@, $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
                $result->valid('time'), $result->valid('color');
    }

    $c->render_json({error=>0, data => $row});
};

get '/vrule/summary/:service_name/:section_name/:graph_name' => sub {
    my ( $self, $c )  = @_; $self->summarize_vrule($c);
};
get '/vrule/summary/:service_name/:section_name' => sub {
    my ( $self, $c )  = @_; $self->summarize_vrule($c);
};
get '/vrule/summary/:service_name' => sub {
    my ( $self, $c )  = @_; $self->summarize_vrule($c);
};
get '/vrule/summary' => sub {
    my ( $self, $c )  = @_; $self->summarize_vrule($c);
};

sub summarize_vrule {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        't' => {
            default => 'all',
            rule => [
                [['CHOICE',qw/all y m w 3d s3d d sd 8h s8h 4h s4h h sh n sn c sc/],'invalid drawing term'],
            ],
        },
        'from' => {
            default => localtime(time-86400*8)->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid From datetime'],
            ],
        },
        'to' => {
            default => localtime()->strftime('%Y/%m/%d %T'),
            rule => [
                [sub{ HTTP::Date::str2time($_[1]) }, 'invalid To datetime'],
            ],
        },
    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $graph_path = '/'.join('/', $c->args->{service_name}||(), $c->args->{section_name}||(), $c->args->{graph_name}||());

    my @vrules;
    eval {
        @vrules = $self->data->get_vrule($result->valid('t'), $result->valid('from'), $result->valid('to'), $graph_path);
    };
    if ( $@ ) {
        die sprintf "Error:%s %s/%s/%s => %s,%s,%s",
            $@, $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
                $result->valid('t'), $result->valid('from') , $result->valid('to');
    }

    $c->render_json(\@vrules);
};

1;

