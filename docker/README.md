# GrowthForecast

GrowthForecast is a web tool that let's you graph all sorts of metrics via a WebAPI. Our simple API let's you create and update charts in real time, customize your charts through a Web interface, and create charts that combine multiple metrics.

Official Site and documents are [here](http://kazeburo.github.io/GrowthForecast/)

## Installing and Booting

### (1) Installing Package Dependencies

We'll first install the libraries that RRDTool depends on using package managers like yum, apt, homebrew, etc.

* glib
* xml2
* pango
* cairo

#### CentOS

```
$ sudo yum groupinstall "Development Tools"
$ sudo yum install pkgconfig glib2-devel gettext libxml2-devel pango-devel cairo-devel
```

### ubuntu

```
$ sudo apt-get build-dep rrdtool
```

### Installing GrowthForecast

We'll use the [cpanm](https://metacpan.org/release/App-cpanminus) command to install GrowthForecast together with its module dependencies.

```
$ cpanm -n GrowthForecast
```

We recommend that you use Perl built with [perlbrew](http://perlbrew.pl/) (or others) rather than the default Perl that ships with your OS.

Please check for version information on [CPAN](https://metacpan.org/release/GrowthForecast). Installation will take a bit of time since there are a many module dependencies.

### (3) Starting GrowthForecast

You've now installed GrowthForecast! To start GrowthForecast, please execute "growthforecast.pl".

```
$ growthforecast.pl --data-dir /home/user/growthforecast
```

If you run it with the data-dir option (specifying the directory to store the graph data), the web server will start on port 5125. You can verify this in your browser.

## Play with Docker

We also have Docker image in docker hub registry. You can play growthforeacst with docker in a following step.

```
$ docker run -p 5125:5125 kazeburo/growthforecast
```

For persistent the graph data, mount your disk to image

```
docker run -p 5125:5125 -v /host/data:/var/lib/growthforecast kazeburo/growthforecast
```




