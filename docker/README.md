# GrowthForecast

GrowthForecast is a web tool that let's you graph all sorts of metrics via a WebAPI. Our simple API let's you create and update charts in real time, customize your charts through a Web interface, and create charts that combine multiple metrics.

Official Site and documents are [here](http://kazeburo.github.io/GrowthForecast/)

## Play with Docker

We also have Docker application image in docker hub registry. You can play growthforeacst with docker in a following step.

```
$ docker run -p 5125:5125 kazeburo/growthforecast
```

For persistent the graph data, mount your disk to image

```
docker run -p 5125:5125 -v /host/data:/var/lib/growthforecast kazeburo/growthforecast
```




