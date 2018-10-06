---
title: "Tokio 是什么？"
weight: 1
menu: "docs"
---

Tokio allows developers to write asynchronous programs in the Rust programming
language. Instead of synchronously waiting for long-running operations like reading
a file or waiting for a timer to complete before moving on to the next thing,
Tokio allows developers to write programs where execution continues while the
long-running operations are in progress.

More specifically, Tokio is an event-driven, non-blocking I/O platform
for writing asynchronous applications with Rust. At a high level, it
provides a few major components:

* A multithreaded, work-stealing based task [scheduler].
* A [reactor] backed by the operating system's event queue (epoll, kqueue,
  IOCP, etc...).
* Asynchronous [TCP and UDP][net] sockets.

These components provide the runtime components necessary for building
an asynchronous application.

[net]: https://docs.rs/tokio/0.1/tokio/net/index.html
[reactor]: https://docs.rs/tokio/0.1/tokio/reactor/index.html
[scheduler]: https://tokio-rs.github.io/tokio/tokio/runtime/index.html

# 快速

Tokio is built on the Rust programming language, which is in of itself very
fast. Applications built with Tokio will get those same benefits. Tokio's design
is also geared towards enabling applications to be as fast as possible.

## 零开销抽象

Tokio is built around [futures]. Futures aren't a new idea, but the way Tokio
uses them is [unique][poll]. Unlike futures from other languages, Tokio's
futures compile down to a state machine. There is no added overhead from
synchronization, allocation, or other costs common with future implementations.

Note that providing zero-cost abstractions does not mean that Tokio itself has
no cost. It means that using Tokio results in an end product with equivalent
overhead to not using Tokio.

## 并发

Out of the box, Tokio provides a multi-threaded, [work-stealing], scheduler. So,
when you start the Tokio runtime, you are already using all of your computer's
CPU cores.

Modern computers increase their performance by adding cores, so being able to
utilize many cores is critical for writing fast applications.

[work-stealing]: https://en.wikipedia.org/wiki/Work_stealing

## 非阻塞 I/O

When hitting the network, Tokio will used the most efficient system available to
the operating system. On Linux this means [epoll], *bsd platforms provide [kqueue],
and Windows has [I/O completion ports][iocp].

This allows multiplexing many sockets on a single thread and receiving
operating system notifications in batches, thus reducing system calls. All this
leads to less overhead for the application.

[epoll]: http://man7.org/linux/man-pages/man7/epoll.7.html
[kqueue]: https://www.freebsd.org/cgi/man.cgi?query=kqueue&sektion=2
[iocp]: https://docs.microsoft.com/en-us/windows/desktop/fileio/i-o-completion-ports

# 可靠

While Tokio cannot prevent all bugs, it is designed to minimize them. It does
this by providing APIs that are hard to misuse. At the end of the day, you can
ship applications to production with confidence.

## 所有权与类型系统

Rust's ownership model and type system enables implementing system level
applications without the fear of memory unsafety. It prevents classic bugs
such as accessing uninitialized memory and use after free. It does this without
adding any run-time overhead.

Further, APIs are able to leverage the type system to provide hard to misuse
APIs. For example, `Mutex` does not require the user to explicitly unlock.

## 反压

In push based systems, when a producer produces data faster than the consumer
can process, data will start backing up. Pending data is stored in memory.
Unless the producer stops producing, the system will eventually run out of
memory and crash. The ability for a consumer to inform the producer to slow down
is backpressure.

Because Tokio uses a [poll] based model, the problem mostly just goes away.
Producers are lazy by default. They will not produce any data unless the
consumer asks them to. This is built into Tokio's foundation.

## 撤销

Because of Tokio's [poll] based model, computations do no work unless they are
polled. Dependents of that computation hold a [future][futures] representing the
result of that computation. If the result is no longer needed, the future is
dropped. At this point, the computation will no longer be polled and thus
perform no more work.

Thanks to Rust's ownership model, the computation is able to implement `drop`
handles to detect the future being dropped. This allows it to perform any
necessary cleanup work.

# 轻量

Tokio scales well without adding overhead to the application, allowing it to
thrive in resource constrained environments.

## 无垃圾回收器

Because Tokio is built on Rust, the compiled executable includes minimal
language run-time. The end product is similar to what C++ would produce. This
means, no garbage collector, no virtual machine, no JIT compilation, and no
stack manipulation. Write your server applications without fear of
[stop-the-world][gc] pauses.

It is possible to use Tokio without incurring any runtime allocations, making it
a good fit for [real-time] use cases.

[gc]: https://en.wikipedia.org/wiki/Garbage_collection_(computer_science)#Disadvantages
[real-time]: https://en.wikipedia.org/wiki/Real-time_computing

## 模块化

While Tokio provides a lot out of the box, it is all organized very modularly.
Each component lives in a separate library. If needed, applications may opt to
pick and choose the needed components and avoid pulling in the rest.

[poll]: {{< ref "/docs/getting-started/runtime-model.md" >}}#polling-model
[futures]: {{< ref "/docs/getting-started/futures.md" >}}

# 示例

A basic TCP echo server with Tokio:

```rust
extern crate tokio;

use tokio::prelude::*;
use tokio::io::copy;
use tokio::net::TcpListener;

fn main() {
# }
# fn hax() {
    // 绑定服务器的套接字。
    let addr = "127.0.0.1:12345".parse().unwrap();
    let listener = TcpListener::bind(&addr)
        .expect("unable to bind TCP listener");

    // 从传入的链接的套接字中取出 stream
    let server = listener.incoming()
        .map_err(|e| eprintln!("accept failed = {:?}", e))
        .for_each(|sock| {
            // 拆分该套接字的读、写
            // 两部分。
            let (reader, writer) = sock.split();

            // 一个回显该数据并返回
            // 复制了多少字节的 future……
            let bytes_copied = copy(reader, writer);

            // ……之后我们会输出所发生的事情。
            let handle_conn = bytes_copied.map(|amt| {
                println!("wrote {:?} bytes", amt)
            }).map_err(|err| {
                eprintln!("IO error {:?}", err)
            });

            // 产生该 future 作为并发任务。
            tokio::spawn(handle_conn)
        });

    // 启动 Tokio 运行时
    tokio::run(server);
}
```

More examples can be found [here](examples).
