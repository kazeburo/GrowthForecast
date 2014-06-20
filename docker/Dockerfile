FROM kazeburo/perl:v5.18
MAINTAINER Masahiro Nagano <kazeburo@gmail.com>

RUN apt-get -y build-dep rrdtool
RUN apt-get install -y fonts-ipafont-gothic

RUN mkdir -p /var/lib/growthforecast

# pre install for dependencies
RUN cpanm -n --no-man-pages --installdeps GrowthForecast
RUN cpanm -n --no-man-pages Module::Install Module::Install::ReadmeFromPod Module::Install::Repository Module::Install::ShareFile Module::Install::CPANfile
RUN apt-get install -y jq

# install
ADD ./README.md /README.md
RUN (echo y;echo n;echo n;echo http://www.cpan.org/;echo o conf commit)|cpan
RUN git clone -b $(curl -s https://api.github.com/repos/kazeburo/GrowthForecast/tags|jq -r '.[0].name') https://github.com/kazeburo/GrowthForecast.git /tmp/GrowthForecast
RUN cpanm -n --no-man-pages -v --no-interactive /tmp/GrowthForecast
RUN rm -rf /tmp/GrowthForecast

EXPOSE 5125
CMD growthforecast.pl --data-dir /var/lib/growthforecast




