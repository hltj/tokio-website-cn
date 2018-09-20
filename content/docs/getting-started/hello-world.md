---
title: "Hello World!"
weight : 1010
menu:
  docs:
    parent: getting_started
---

为了开始我们的 Tokio 之旅，我们会以惯例“hello world”开始<!--
-->。这个服务器会监听接入的连接。收到连接<!--
-->后，它会向客户端写入“hello world”并关闭连接。

让我们开始吧。

首先，生成一个新的 crate。

```bash
$ cargo new --bin hello-world
$ cd hello-world
```

接下来，添加必要的依赖项：

```toml
[dependencies]
tokio = "0.1"
```

还有 `main.rs` 中的 crate 与类型：

```rust
# #![deny(deprecated)]
extern crate tokio;

use tokio::io;
use tokio::net::TcpListener;
use tokio::prelude::*;
# fn main() {}
```

# 编写服务器

第一步是将 `TcpListener` 绑定到本地端口。我们使用
Tokio 提供的 `TcpListener` 实现。

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::io;
# use tokio::net::TcpListener;
# use tokio::prelude::*;
fn main() {
    let addr = "127.0.0.1:6142".parse().unwrap();
    let listener = TcpListener::bind(&addr).unwrap();

    // 后续片段写到这里……
}
```

接下来，我们定义服务器任务。这个异步任务会监听<!--
-->在已绑定的监听器上接入的连接，并处理每个已接受连接。

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::io;
# use tokio::net::TcpListener;
# use tokio::prelude::*;
# fn main() {
#     let addr = "127.0.0.1:6142".parse().unwrap();
#     let listener = TcpListener::bind(&addr).unwrap();
let server = listener.incoming().for_each(|socket| {
    println!("accepted socket; addr={:?}", socket.peer_addr().unwrap());

    // 这里处理套接字。

    Ok(())
})
.map_err(|err| {
    // 所有任务必须具有 `()` 类型的 `Error`。这会强制进行
    // 错误处理，并且有助于避免静默故障。
    //
    // 在本例中，只是将错误记录到 STDOUT（标准输出）。
    println!("accept error = {:?}", err);
});
# }
```

调用 `listener.incoming()` 会返回一个已接受连接的 [`Stream`]。
[`Stream`] 有点像异步迭代器。每次接受套接字时，`for_each` 方法都会产生<!--
-->新的套接字。`for_each` 是组合子函数的一个示例，
它定义了如何处理异步作业。

每个组合子函数都获得必要状态的所有权以及用<!--
-->以执行的回调，并返回一个新的 `Future` 或者是有附加“步骤”顺次排入的 `Stream`<!--
-->。

返回的那些 future 与 stream 都是惰性的，也就是说，在调用该组合子时不执行任何操作<!--
-->。相反，一旦所有异步步骤都已顺次排入，
最终的 `Future`（代表该任务）就会“产生”。这是<!--
-->之前定义的作业开始运行的时候。

我们稍后会深入探讨这些 future 与 stream。

# 运行服务器

到目前为止，我们有一个表示服务器会完成的作业的 future，但是我们<!--
-->需要一种方式来产生（即运行）该作业。我们需要一个执行子。

执行子负责调度异步任务，使其<!--
-->完成。有很多执行子的实现可供选择，每个都有<!--
-->不同的优缺点。在本例中，我们会使用 [Tokio 运行时][rt]。

Tokio 运行时是为异步应用程序预配置的运行时。它<!--
-->包含一个线程池作为默认执行子。该线程池已经为<!--
-->在异步应用程序中使用而调整好。

```rust
# #![deny(deprecated)]
# extern crate tokio;
# extern crate futures;
#
# use tokio::io;
# use tokio::net::TcpListener;
# use tokio::prelude::*;
# use futures::future;
# fn main() {
# let server = future::ok(());

println!("server running on localhost:6142");
tokio::run(server);
# }
```

`tokio::run` 会启动该运行时，阻塞当前进程直到<!--
-->所有已产生的任务都已完成并且所有资源（如 TCP 套接字）都已<!--
-->释放。

至此，我们仅仅在执行子上执行了单个任务，因此 `server` 任务<!--
-->是阻塞 `run` 返回的唯一任务。

接下来，我们会处理入站套接字。

# 写数据

我们的目标是对每个已接受的套接字写入 `"hello world\n"`。我们会这样做：<!--
-->通过定义一个新的异步任务来执行写操作，并在<!--
-->同一执行子上产生该任务。

回到 `incoming().for_each` 块。

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::io;
# use tokio::net::TcpListener;
# use tokio::prelude::*;
# fn main() {
#     let addr = "127.0.0.1:6142".parse().unwrap();
#     let listener = TcpListener::bind(&addr).unwrap();
let server = listener.incoming().for_each(|socket| {
    println!("accepted socket; addr={:?}", socket.peer_addr().unwrap());

    let connection = io::write_all(socket, "hello world\n")
        .then(|res| {
            println!("wrote message; success={:?}", res.is_ok());
            Ok(())
        });

    // 产生一个处理该套接字的新任务：
    tokio::spawn(connection);

    Ok(())
})
# ;
# }
```

我们正在定义另一个异步任务。这个任务会取得该套接字的所有权<!--
-->、对该套接字写入信息，然后完成。`connection`
变量保存了其最终任务。同样，此时还没有执行任何作业。

`tokio::spawn` 用于在运行时产生任务。因为
`server` future 会在运行时上运行，所以我们可以产生更多任务。
如果在运行时外部调用 `tokio::spawn`，它会恐慌（panic）。

[`io::write_all`] 函数获取 `socket` 的所有权并返回一个
[`Future`]，一旦整个消息都已写入到该套接字中，这个 future 就会完成<!--
-->。`then` 用于排入当写操作完成后运行的步骤<!--
-->。在本例中，我们只向 `STDOUT` 写一条消息，表明<!--
-->写操作已完成。

请注意 `res` 是一个包含原始套接字的 `Result`。这让我们可以<!--
-->在同一个套接字上顺次排入附加的读取或写入。然而，我们并<!--
-->没有任何事情可做，所有我们只是释放该套接字，即可关闭该套接字。

可以在[这里][full-code]找到完整的示例

## 下一步

我们这里只是对 Tokio 及其异步模型小试牛刀。本指南的下一页<!--
-->会开始深入探讨 Tokio 运行时模型。

[`Future`]: {{< api-url "futures" >}}/future/trait.Future.html
[`Stream`]: {{< api-url "futures" >}}/stream/trait.Stream.html
[rt]: {{< api-url "tokio" >}}/runtime/index.html
[`io::write_all`]: {{< api-url "tokio-io" >}}/io/fn.write_all.html
[`tokio::spawn`]: {{< api-url "tokio" >}}/fn.spawn.html
[full-code]:https://github.com/tokio-rs/tokio/blob/master/examples/hello_world.rs
