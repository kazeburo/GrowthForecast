FROM centos
MAINTAINER Masahiro Nagano <kazeburo@gmail.com>

RUN yum -y groupinstall "Development Tools"
RUN yum -y install pkgconfig glib2-devel gettext libxml2-devel pango-devel cairo-devel git ipa-gothic-fonts
RUN git clone https://github.com/tagomoris/xbuild.git
RUN xbuild/perl-install 5.18.1 /opt/perl-5.18
RUN echo 'export $PATH=/opt/perl-5.18/bin:$PATH' > /etc/profile.d/xbuild-perl.sh
RUN /opt/perl-5.18/bin/cpanm -n GrowthForecast
RUN mkdir -p /var/lib/growthforecast
EXPOSE 5125
CMD ["/opt/perl-5.18/bin/growthforecast.pl","--data-dir","/var/lib/growthforecast"]

