# clyso-tools-container

## How to use 

There are prebuilt containers for each Ceph version and to get a shell.

```
./clyso-tools.sh --version 20.2.0
```

Passing in a --debug flag let's the container share namespace with the host which can be useful for using tracing tools
```
$ ./clyso-tools.sh --version 20.2.0 --debug
```

Inside the container, to access /root filesystem, one can go to /rootfs/root

Available containers for these Ceph versions:

harbor.clyso.com/clyso-tools/clyso-tools:v20.2.0
harbor.clyso.com/clyso-tools/clyso-tools:v19.2.3
harbor.clyso.com/clyso-tools/clyso-tools:v18.2.7
harbor.clyso.com/clyso-tools/clyso-tools:v20.2.1
harbor.clyso.com/clyso-tools/clyso-tools:v18.2.8
harbor.clyso.com/clyso-tools/clyso-tools:v19.2.4

## What is in this container?

clyso specific tools:
- o8 TUI for ceph
- otto cli analyzer tool
- upmap-remapped.py

Inside this container are the added tools we have
```
[/usr/local/bin]# ls
o8  osdtrace  otto  radostrace  unwindpmp upmap-remapped.py
```

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

### cephtrace - eBPF Tracing Tools

The container includes [cephtrace](https://github.com/taodd/cephtrace) - a suite of eBPF-based dynamic tracing tools for Ceph. These tools provide microsecond-level visibility into your Ceph cluster's performance.

**Available tools:**
- **osdtrace** - Trace OSD operations with detailed latency breakdown
- **radostrace** - Trace librados client operations in real-time (RGW, QEMU/KVM VMs, userspace RBD)

**Pre-compiled DWARF files** are included at:
- `/usr/local/share/cephtrace/osdtrace-dwarf.json`
- `/usr/local/share/cephtrace/radostrace-dwarf.json`

These DWARF files are pre-generated for the specific Ceph version in the container, so you can start tracing immediately without needing debug symbols.

#### Example: Trace OSD operations

```bash
# Start container in debug mode (required for tracing)
./clyso-tools.sh --version 20.2.0 --debug

# Inside container, find OSD process on host
ps aux | grep ceph-osd

osdtrace -i /usr/local/share/cephtrace/osdtrace-dwarf.json -p <osd-pid> -x --skip-version-check
```

#### Example: Trace client operations

```bash
# Find client process (e.g., radosgw)
ps aux | grep radosgw
radostrace -i /usr/local/share/cephtrace/radostrace-dwarf.json -p <radosgw-pid> --skip-version-check

# For QEMU/KVM VMs (userspace RBD):
ps aux | grep qemu
radostrace -i /usr/local/share/cephtrace/radostrace-dwarf.json -p <qemu-pid> --skip-version-check
```

**For more information and detailed documentation**, see the [cephtrace GitHub repository](https://github.com/taodd/cephtrace).

### extra packages

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
 fio \
```
