FROM centos:6.4
MAINTAINER Masahiro Nagano <kazeburo@gmail.com>

# fix locale error. requires for centos:latest
# RUN yum -y reinstall glibc-common

RUN yum -y groupinstall "Development Tools"
RUN yum -y install pkgconfig glib2-devel gettext libxml2-devel pango-devel cairo-devel git ipa-gothic-fonts

RUN git clone https://github.com/tagomoris/xbuild.git
RUN xbuild/perl-install 5.18.1 /opt/perl-5.18

RUN /opt/perl-5.18/bin/cpanm -n --installdeps GrowthForecast
RUN echo 'export PATH=/opt/perl-5.18/bin:$PATH' > /etc/profile.d/xbuild-perl.sh
ENV PATH opt/perl-5.18/bin:${PATH}

RUN mkdir -p /var/lib/growthforecast
ADD ./README.md ./
RUN git clone https://github.com/kazeburo/GrowthForecast.git /opt/growthforecast
RUN cd /opt/growthforecast; /opt/perl-5.18/bin/cpanm -n --installdeps .

EXPOSE 5125
CMD perl /opt/growthforecast/growthforecast.pl --data-dir /var/lib/growthforecast




