# clyso-tools-build

## How to use 

There are prebuilt containers for each ceph version and to get a shell

```
./clyso-tools.sh --version 20.2.0
```

Passing in a --debug flag let's the container share namespace with the host which can be useful for using tracing tools
```
$ ./clyso-tools.sh --version 20.2.0 --debug
```

Inside the container, to access /root filesystem, one can go to /rootfs/root

## What is in this container?

clyso specific tools:
- o8 TUI for ceph
- otto cli analyzer tool

### wallclock profiler

Passing in the --debug is needed to get the PIDs of the ceph processes to attach to.
```
$ ./clyso-tools.sh --version 20.2.0 --debug
$ ps aux | grep osd
user      pid     command
167       990404  /usr/bin/ceph-osd -n osd.2 ...

$ unwindpmp -p 990404

Thread 991782 (tp_osd_tp) - 100 samples
+ 100.00% __clone3
 + 100.00% start_thread
  + 100.00% ShardedThreadPool::shardedthreadpool_worker(unsigned int)
   + 100.00% ShardedThreadPool::shardedthreadpool_worker(unsigned int)
    + 100.00% OSD::ShardedOpWQ::_process(unsigned int, ceph::heartbeat_handle_d*)
...
...
```


```
$ unwindpmp -p <pid>

Usage:
  ./unwindpmp [OPTION...]

  -h, --help           show this help message and exit
  -p, --pid arg        PID of the process to attach to.
  -s, --sleep arg      The time to sleep between samples in ms.
  -n, --samples arg    The number of samples to collect.
  -t, --threshold arg  Ignore results below the threshold when making the
                       callgraph.
  -v, --invert         Print inverted callgraph.
  -w, --max_width arg  Set the display width (default is terminal width)
  -r, --truncate       Truncate lines to the terminal width

```

extra packages

```
 elfutils-libs \
 strace \
 gdb \
 ltrace \
 lsof \
 tcpdump \
 sysstat \
 perf \
 bcc-tools \
 util-linux \
 procps-ng \
 iproute \
```
