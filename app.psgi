use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Plack::Builder;
use GrowthForecast::Web;

my $root_dir = File::Basename::dirname(__FILE__);

my $app = GrowthForecast::Web->psgi($root_dir);
builder {
    enable 'ReverseProxy';
    enable 'Static',
        path => qr!^/(?:(?:css|js|images)/|favicon\.ico$)!,
        root => $root_dir . '/public';
    $app;
};

