FROM centos:6.4
MAINTAINER Masahiro Nagano <kazeburo@gmail.com>

# fix locale error. requires for centos:latest
# RUN yum -y reinstall glibc-common

RUN yum -y install gcc make pkgconfig glib2-devel gettext libxml2-devel pango-devel cairo-devel git ipa-gothic-fonts; yum clean all

RUN git clone https://github.com/tagomoris/xbuild.git
RUN xbuild/perl-install 5.18.1 /opt/perl-5.18
RUN rm -rf /opt/perl-5.18/man
ENV PATH /opt/perl-5.18/bin:${PATH}
RUN echo 'export PATH=/opt/perl-5.18/bin:$PATH' > /etc/profile.d/xbuild-perl.sh

# pre install for dependencies
RUN /opt/perl-5.18/bin/cpanm -n --no-man-pages --installdeps GrowthForecast; rm -rf .cpanm

RUN mkdir -p /var/lib/growthforecast
ADD ./README.md ./
RUN git clone --depth 1 https://github.com/kazeburo/GrowthForecast.git /opt/growthforecast
RUN cd /opt/growthforecast; /opt/perl-5.18/bin/cpanm -n --no-man-pages --installdeps .

EXPOSE 5125
CMD perl /opt/growthforecast/growthforecast.pl --data-dir /var/lib/growthforecast




