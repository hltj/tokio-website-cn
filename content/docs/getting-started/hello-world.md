---
title: "Hello World!"
weight : 1010
menu:
  docs:
    parent: getting_started
---

为了开始我们的 Tokio 之旅，我们会以惯例“hello world”开始<!--
-->。 This program will create a TCP stream and write "hello, world!" to the stream.
The difference between this and a Rust program that writes to a TCP stream without Tokio
is that this program won't block program execution when the stream is created or when
our "hello, world!" message is written to the stream.

在开始之前，你应该对 TCP stream 的工作原理有最基本的了解。
了解 Rust 的[标准库实现](https://doc.rust-lang.org/std/net/struct.TcpStream.html)<!--
-->也很有帮助。

我们开始吧。

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
use tokio::net::TcpStream;
use tokio::prelude::*;
# fn main() {}
```

# Creating the stream

第一步是创建 `TcpStream`。我们使用 Tokio 提供的 `TcpStream`
实现。

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::net::TcpStream;
fn main() {
    // Parse the address of whatever server we're talking to
    let addr = "127.0.0.1:6142".parse().unwrap();
    let stream = TcpStream::connect(&addr);

    // 后续片段写到这里……
}
```

接下来，我们定义  `client` 任务。这个异步任务会 create the stream
and then yield the stream once it's been created for additional processing.

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::net::TcpStream;
# use tokio::prelude::*;
# fn main() {
# let addr = "127.0.0.1:6142".parse().unwrap();
let hello_world = TcpStream::connect(&addr).and_then(|stream| {
    println!("created stream");

    // 这里处理 stream。

    Ok(())
})
.map_err(|err| {
    // 所有任务必须具有 `()` 类型的 `Error`。这会强制进行
    // 错误处理，并且有助于避免静默故障。
    //
    // 在本例中，只是将错误记录到 STDOUT（标准输出）。
    println!("connection error = {:?}", err);
});
# }
```

调用 `TcpStream::connect` 会返回一个已创建的 TCP stream 的 [`Future`]。
我们会在指南的后续部分学习更多关于 [`Futures`] 的内容，不过现在你可以将
[`Stream`] as a value that represents something that will eventually happen in the
future (in this case the stream will be created). This means that `TcpStream::connect` does
not wait for the stream to be created before it returns. Rather it returns immediately
with a value representing the work of creating a TCP stream. We'll see down below when this work
_actually_ gets executed.

The `and_then` method yields the stream once it has been created. `and_then` 是<!--
-->定义了如何处理异步作业的组合子函数的一个示例。

每个组合子函数都获得必要状态的所有权以及用<!--
-->以执行的回调，并返回一个新的有附加“步骤”顺次排入的 `Future`<!--
-->。`Future` 是表示会在未来的某个时刻完成的<!--
-->某些计算的值。

值得重申的是返回的那些 future 都是惰性的，也就是说，在调用该组合子时不执行任何操作<!--
-->。相反，一旦所有异步步骤都已顺次排入，
最终的 `Future`（代表整个任务）就会“产生”（即运行）。这是<!--
-->之前定义的作业开始运行的时候。 In other words, the code
we've written so far does not actually create a TCP stream.

我们稍后会更深入地探讨这些 future（以及 stream 与 sink 的相关概念）<!--
-->。

It's also important to note that we've called `map_err` to convert whatever error
we may have gotten to `()` before we can actually run our future. This ensures that
we acknowledge errors.

Next, we will process the stream.

# 写数据

我们的目标是将 `"hello world\n"` 写入到 stream。

回到 `TcpStream::connect(addr).and_then` 块：

```rust
# #![deny(deprecated)]
# extern crate tokio;
#
# use tokio::io;
# use tokio::prelude::*;
# use tokio::net::TcpStream;
# fn main() {
# let addr = "127.0.0.1:6142".parse().unwrap();
let client = TcpStream::connect(&addr).and_then(|stream| {
    println!("created stream");

    io::write_all(stream, "hello world\n").then(|result| {
      println!("wrote to stream; success={:?}", result.is_ok());
      Ok(())
    })
})
# ;
# }
```

The [`io::write_all`] function takes ownership of `stream`, returning a
[`Future`] that completes once the entire message has been written to the
stream. `then` is used to sequence a step that gets run once the write has
completed. In our example, we just write a message to `STDOUT` indicating that
the write has completed.

Note that `result` is a `Result` that contains the original stream. This allows us
to sequence additional reads or writes to the same stream. However, we have
nothing more to do, so we just drop the stream, which automatically closes it.

# Running the client task

到目前为止，我们有一个表示程序会完成的作业的 `Future`，但是我们<!--
-->并没有真正运行它。需要一种方式来“产生”该作业。我们需要一个执行子。

执行子负责调度异步任务，使其<!--
-->完成。有很多执行子的实现可供选择，每个都有<!--
-->不同的优缺点。在本例中，我们会使用
[Tokio 运行时][rt] 的默认执行子。

```rust
# #![deny(deprecated)]
# extern crate tokio;
# extern crate futures;
#
# use tokio::prelude::*;
# use futures::future;
# fn main() {
# let client = future::ok(());
println!("About to create the stream and write to it...");
tokio::run(client);
println!("Stream has been created and written to.");
# }
```

`tokio::run` 会启动该运行时，阻塞当前进程直到所有已产生的任务<!--
-->都已完成并且所有资源（如文件与套接字）都已释放。

至此，我们仅仅在执行子上执行了单个任务，因此 `client` 任务<!--
-->是阻塞 `run` 返回的唯一任务。 Once `run` has returned we can be sure
that our Future has been run to completion.

可以在[这里][full-code]找到完整的示例。

## 下一步

我们这里只是对 Tokio 及其异步模型小试牛刀。本指南的下一页<!--
-->会开始深入探讨 Tokio 运行时模型。

[`Future`]: {{< api-url "futures" >}}/future/trait.Future.html
[rt]: {{< api-url "tokio" >}}/runtime/index.html
[`io::write_all`]: {{< api-url "tokio-io" >}}/io/fn.write_all.html
[full-code]:https://github.com/tokio-rs/tokio/blob/master/examples/hello_world.rs
