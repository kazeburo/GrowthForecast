package GrowthForecast::Web;

use strict;
use warnings;
use utf8;
use Kossy;
use Time::Piece;
use GrowthForecast::Data;
use GrowthForecast::RRD;
use Log::Minimal;

sub data {
    my $self = shift;
    $self->{__data} ||= GrowthForecast::Data->new($self->root_dir);
    $self->{__data};
}

sub rrd {
    my $self = shift;
    $self->{__rrd} ||= GrowthForecast::RRD->new($self->root_dir);
    $self->{__rrd};
}

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
    $c->render('docs.tx',{});
};

get '/add_complex' => sub {
    my ( $self, $c )  = @_;
    my $graphs = $self->data->get_all_graph_name();
    $c->render('add_complex.tx',{ graphs => $graphs });
};

get '/edit_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    my $graphs = $self->data->get_all_graph_name();
    $c->render('edit_complex.tx',{ graphs => $graphs });
};

post '/remove_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    $self->data->remove_complex($c->stash->{complex}->{id});
    $c->render_json({
        error => 0,
    });
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
    my $result = $c->req->validator([
        'service_name' => {
            rule => [
                ['NOT_NULL', 'サービス名がありません'],
            ],
        },
        'section_name' => {
            rule => [
                ['NOT_NULL', 'セクション名がありません'],
            ],
        },
        'graph_name' => {
            rule => [
                ['NOT_NULL', 'グラフ名がありません'],
                [$self->check_uniq_complex,'同じ名前のグラフがあります'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',0..19], '値が正しくありません'],
            ],
        },
        'type-1' => {
            rule => [
                ['NOT_NULL', 'データタイプがありません'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'データタイプが正しくありません'],
            ],
        },
        'path-1' => {
            rule => [
                ['NOT_NULL', 'パスがありません'],
                ['NATURAL', 'パスが正しくありません'],
            ],
        },
        'gmode-1' => {
            rule => [
                ['NOT_NULL', 'モードがありません'],
                [['CHOICE',qw/gauge subtract/], 'モードが正しくありません'],
            ],
        },
        '@type-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(タイプ)'],
                ['NOT_NULL','データが正しくありません(タイプ)'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'データが正しくありません(タイプ)'],
            ],
        },
        '@path-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(パス)'],
                ['NOT_NULL','データが正しくありません(パス)'],
                ['NATURAL', 'データが正しくありません(パス)'],
            ],
        },
        '@gmode-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(モード)'],
                ['NOT_NULL', 'データが正しくありません(モード)'],
                [['CHOICE',qw/gauge subtract/], 'データが正しくありません(モード)'],
            ],
        },
        '@stack-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(スタック)'],
                ['NOT_NULL', 'データが正しくありません(スタック)'],
                [['CHOICE',qw/0 1/], 'データが正しくありません(スタック)'],
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
        location => $c->req->uri_for('/list/'.$result->valid('service_name').'/'.$result->valid('section_name'))->as_string,
    });
};


post '/edit_complex/:complex_id' => [qw/get_complex/] => sub {
    my ( $self, $c )  = @_;
    my @type2 = $c->req->param('type-2');
    my $type2_num = scalar @type2;
    $type2_num = 1 if !$type2_num;
    my $result = $c->req->validator([
        'service_name' => {
            rule => [
                ['NOT_NULL', 'サービス名がありません'],
            ],
        },
        'section_name' => {
            rule => [
                ['NOT_NULL', 'セクション名がありません'],
            ],
        },
        'graph_name' => {
            rule => [
                ['NOT_NULL', 'グラフ名がありません'],
                [$self->check_uniq_complex($c->stash->{complex}->{id}),'同じ名前のグラフがあります'],
            ],
        },
        'description' => {
            default => '',
            rule => [],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',0..19], '値が正しくありません'],
            ],
        },
        'type-1' => {
            rule => [
                ['NOT_NULL', 'データタイプがありません'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'データタイプが正しくありません'],
            ],
        },
        'path-1' => {
            rule => [
                ['NOT_NULL', 'パスがありません'],
                ['NATURAL', 'パスが正しくありません'],
            ],
        },
        'gmode-1' => {
            rule => [
                ['NOT_NULL', 'モードがありません'],
                [['CHOICE',qw/gauge subtract/], 'モードが正しくありません'],
            ],
        },
        '@type-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(タイプ)'],
                ['NOT_NULL','データが正しくありません(タイプ)'],
                [['CHOICE',qw/AREA LINE1 LINE2/], 'データが正しくありません(タイプ)'],
            ],
        },
        '@path-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(パス)'],
                ['NOT_NULL','データが正しくありません(パス)'],
                ['NATURAL', 'データが正しくありません(パス)'],
            ],
        },
        '@gmode-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(モード)'],
                ['NOT_NULL', 'データが正しくありません(モード)'],
                [['CHOICE',qw/gauge subtract/], 'データが正しくありません(モード)'],
            ],
        },
        '@stack-2' => {
            rule => [
                [['@SELECTED_NUM',$type2_num,$type2_num], 'データが正しくありません(スタック)'],
                ['NOT_NULL', 'データが正しくありません(スタック)'],
                [['CHOICE',qw/0 1/], 'データが正しくありません(スタック)'],
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
        location => $c->req->uri_for('/list/'.$result->valid('service_name').'/'.$result->valid('section_name'))->as_string,
    });
};

get '/list/:service_name/:section_name' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator([
        't' => {
            default => 'd',
            rule => [
                [['CHOICE',qw/h m/],'invalid browse term'],
            ],
        },
    ]);
    my $rows = $self->data->get_graphs(
        $c->args->{service_name}, $c->args->{section_name}
    );
    $c->halt(404) unless scalar @$rows;
    $c->render('list.tx',{ graphs => $rows });
};

my $GRAPH_VALIDATOR = [
    't' => {
        default => 'd',
        rule => [
            [['CHOICE',qw/y m w d h n c/],'invalid drawing term'],
        ],
    },
    'gmode' => {
        default => 'gauge',
        rule => [
            [['CHOICE',qw/gauge subtract/],'invalid drawing data'],
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
];

get '/graph/:complex' => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator($GRAPH_VALIDATOR);
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
    my $img = $self->rrd->graph(
        \@data, $result->valid->as_hashref
    );

    $c->res->content_type('image/png');
    $c->res->body($img);
    return $c->res;
};


get '/graph/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;
    my $result = $c->req->validator($GRAPH_VALIDATOR);

    my $img = $self->rrd->graph(
        $c->stash->{graph}, $result->valid->as_hashref
    );

    $c->res->content_type('image/png');
    $c->res->body($img);
    return $c->res;
};

post '/graph/:service_name/:section_name/:graph_name' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;

    my $result = $c->req->validator([
        'description' => {
            default => '',
            rule => [],
        },
        'sort' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',0..19], '値が正しくありません'],
            ],
        },
        'gmode' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',qw/gauge subtract both/], '値が正しくありません'],
            ],
        },
        'adjust' => {
            default => '*',
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE','*','/'], '値が正しくありません'],
            ]
        },
        'adjustval' => {
            default => '1',
            rule => [
                ['NOT_NULL', '正しくありません'],
                ['NATURAL', '1以上の数値にしてください'],
            ],
        },
        'unit' => {
            default => '',
            rule => [],
        },
        'color' => {
            rule => [
                ['NOT_NULL', '正しくありません'],
                [sub{ $_[1] =~ m!^#[0-9A-F]{6}$!i }, '#000000の形式で入力してください'],
            ],
        },
        'type' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',qw/AREA LINE1 LINE2/], '値が正しくありません'],
            ],
        },
        'stype' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                [['CHOICE',qw/AREA LINE1 LINE2/], '値が正しくありません'],
            ],
        },
        'llimit' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                ['INT', '値が正しくありません'],
            ],
        },
        'ulimit' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                ['INT', '値が正しくありません'],
            ],
        },
        'sllimit' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                ['INT', '値が正しくありません'],
            ],
        },
        'sulimit' => {
            rule => [
                ['NOT_NULL', '値がありません'],
                ['INT', '値が正しくありません'],
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
    });
};

post '/graph/:service_name/:section_name/:graph_name/delete' => [qw/get_graph/] => sub {
    my ( $self, $c )  = @_;

    $self->data->remove($c->stash->{graph}->{id});
    $self->rrd->remove($c->stash->{graph});

    $c->render_json({
        error => 0,
    });
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
                ['NOT_NULL','number is null'],
                ['INT','number is not null']
            ],
        },
        'mode' => {
            default => 'gauge',
            rule => [
                [['CHOICE',qw/count gauge/],'count or gauge']
            ],
        }
    ]);

    if ( $result->has_error ) {
        my $res = $c->render_json({
            error => 1,
            messages => $result->messages
        });
        $res->status(400);
        return $res;
    }

    my $row = $self->data->update(
        $c->args->{service_name}, $c->args->{section_name}, $c->args->{graph_name},
        $result->valid('number'), $result->valid('mode')
    );
    $c->render_json({ error => 0, data => $row });
};

1;

