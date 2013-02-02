use strict;
use warnings;
use Test::More;
use Test::Requires {
    RRDs => 0,
};

use_ok $_ for qw(
    GrowthForecast
    GrowthForecast::Web
);

done_testing;


