# Benchmark RRD

Benchmark the rrdupdate without rrdcached vs with rrdcached

## Machine Specs

Details are secret, but HDD anyway. Memory is plenty.

## Without rrdcached

### Procedures

Create rrd files beforehand. 

    $ perl eg/benchmark_rrd.pl -n 600000 --create

Repeat the following procedures with varying numbers (-n option):

Drop disk caches before the measurement

    # echo 3 > /proc/sys/vm/drop_caches

Run the benchmark script

    $ perl eg/benchmark_rrd.pl -n 1000 -r 3

### Results

| # of rrds | 1st (s) (no diskcache) | 2nd (s) | 3rd (s) |
| --------- |:----------------------:|:-------:| -------:|
|  1000     |   1.901                |   0.030 |   0.028 |
|  5000     |  13.857                |   0.319 |   0.146 |
| 10000     |  74.367                |   0.924 |   0.304 |
| 20000     | 101.990                |   4.249 |   0.621 |
| 40000     | 280.950                |  57.372 |   4.628 |
| 60000     | 598.367                | 153.301 |  96.123 |

## With rrdcached

### Procesures

Create rrd files beforehand. 

    $ perl eg/benchmark_rrd.pl -n 600000 --create

Start the rrdcached

    $ rrdcached -w 60 -g -l 'unix:/tmp/rrdcached.sock' -p /tmp/rrdcached.pid

Repeat the following procedures with varying numbers (-n option):

Drop disk caches before the measurement

    # echo 3 > /proc/sys/vm/drop_caches

Run the benchmark script once

    $ perl eg/benchmark_rrd.pl -n 1000 -r 1 -d 'unix:/tmp/rrdcached.sock'

Look the `iostat -dxt 1`, and measure the time to go down since the %util goes up. 

    $ iostat -dxt 1

Without dropping the disk caches, do the same thing 2 times more for 2nd, 3rd.

### Results

| # of rrds | rrdupdate / rrdcached 1st (s) (no diskcache) | 2nd (s)     | 3rd (s)     |
| --------- |:--------------------------------------------:|:-----------:| -----------:|
|  1000     | 0.142 / 4                                    | 0.037 / 1   | 0.037 / 1   |
|  5000     | 0.481 / 15                                   | 0.179 / 2   | 0.181 / 1   |
| 10000     | 0.819 / 45                                   | 0.357 / 2   | 0.363 / 4   |
| 20000     | 1.472 / 65                                   | 0.733 / 6   | 0.716 / 4   |
| 40000     | 2.632 / 180                                  | 1.452 / 112 | 1.437 / 90  |
| 60000     | 1.672 / 282                                  | 2.199 / 144 | 2.374 / 41  |

## Conclusion

1. rrdcached is 1.5 times faster than no-rrdcached if no diskcache is available. 
2. When diskcache is effective, rrdcached does not matter so much. 

## Author

Naotoshi Seo <sonots {at} gmail.com>

