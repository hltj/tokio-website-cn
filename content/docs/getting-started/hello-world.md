---
title: "Hello World!"
weight : 1010
menu:
  docs:
    parent: getting_started
---

为了开始我们的 Tokio 之旅，我们会以惯例“hello world”开始<!--
-->。 这个程序会创建一个 TCP 流并将“hello, world!”写入到流中。
这与未使用 Tokio 写入到 TCP 流的 Rust 程序之间的区别<!--
-->在于，这个程序在创建流或者<!--
-->将“hello, world!”消息写入到流中的时候不会阻塞程序执行。

在开始之前，你应该对 TCP 流的工作原理有最基本的了解<!--
-->。了解 Rust 的[标准库<!--
-->实现](https://doc.rust-lang.org/std/net/struct.TcpStream.html)<!--
-->也很有帮助。

我们开始吧。

首先，生成一个新的 crate。

```bash
$ cargo new hello-world
$ cd hello-world
```

接下来，在 `Cargo.toml` 中添加必要的依赖项：

```toml
[dependencies]
tokio = { version = "0.2", features = ["full"] }
```

Tokio requires specifying the requested components using feature flags. This
allows the user to only include what is needed to run the application, resulting
in smaller binaries. For getting started, we depend on `full`, which includes
all components.

Next, add the following to `main.rs`:

```rust
# #![deny(deprecated)]
# #![allow(unused_imports)]

use tokio::io;
use tokio::net::TcpStream;
use tokio::prelude::*;

#[tokio::main]
async fn main() {
    // application comes here
}
```

这里我们使用 Tokio 自己的 [`io`] 与 [`net`] 模块。这俩模块提供与
`std` 中相应模块几乎相同的网络与 I/O 操作的抽象，
只有一点差异：所有操作都是异步执行的。

Next is the Tokio application entry point. This is an `async` main function
annotated with `#[tokio::main]`. This is the function that first runs when the
binary is executed. The `#[tokio::main]` annotation informs Tokio that this is
where the runtime (all the infrastructure needed to power Tokio) is started.

# Creating the TCP stream

第一步是创建 `TcpStream`。我们使用 Tokio 提供的 `TcpStream`
实现。

```rust,no_run
# #![deny(deprecated)]
#
# use tokio::net::TcpStream;
#[tokio::main]
async fn main() {
    // Connect to port 6142 on localhost
    let stream = TcpStream::connect("127.0.0.1:6142").await.unwrap();

    // Following snippets come here...
# drop(stream);
}
```

`TcpStream::connect` is an _asynchronous_ function. No work is done during the
function call. Instead, `.await` is called to pause the current task until the
connect has completed. Once the connect has completed, the task resumes. The
`.await` call does **not** block the current thread.

Next, we do work with the TCP stream.

# 写数据

我们的目标是将 `"hello world\n"` 写入到流中。

```rust,no_run
# #![deny(deprecated)]
#
# use tokio::net::TcpStream;
# use tokio::prelude::*;
# #[tokio::main]
# async fn main() {
// Connect to port 6142 on localhost
let mut stream = TcpStream::connect("127.0.0.1:6142").await.unwrap();

stream.write_all(b"hello world\n").await.unwrap();

println!("wrote to stream");
# }
```

The [`write_all`] function is implemented for all "stream" like types. It is
provided by the [`AsyncWriteExt`] trait. Again, the function is asynchronous, so
no work is done unless `.await` is called. We call `.await` to perform the
write.

可以在[这里][full-code]找到完整的示例。

# 运行该代码

[Netcat] 是一个在命令行快速创建 TCP 套接字的工具。以下<!--
-->命令在先前指定的端口上启动 TCP 套接字监听。

```bash
$ nc -l 6142
```
> 上述命令用于 GNU 版的 netcat，该命令存在于许多<!--
> -->基于 unix 的操作系统。而以下命令可用于
> [NMap.org][NMap.org] 版的 netcat：`$ ncat -l 6142`

在另一个终端运行我们的项目。

```bash
$ cargo run
```

如果一切顺利，你会看到 Netcat 输出的 `hello world`。

# 下一步

我们这里只是对 Tokio 及其异步模型小试牛刀。本指南的下一页<!--
-->会开始稍深入探讨 Future 与 Tokio 运行时模型。

[`io`]: https://docs.rs/tokio/0.2/tokio/io/index.html
[`net`]: https://docs.rs/tokio/0.2/tokio/net/index.html
[`write_all`]: https://docs.rs/tokio/0.2/tokio/io/trait.AsyncWriteExt.html#method.write_all
[`AsyncWriteExt`]: https://docs.rs/tokio/0.2/tokio/io/trait.AsyncWriteExt.html
[full-code]: https://github.com/tokio-rs/tokio/blob/master/examples/hello_world.rs
[Netcat]: http://netcat.sourceforge.net/
[Nmap.org]: https://nmap.org
