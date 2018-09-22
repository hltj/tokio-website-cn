---
title: "运行时模型"
weight : 1020
menu:
  docs:
    parent: getting_started
---

现在我们要介绍 Tokio / future 运行时模型。Tokio 建立在
[`futures`] crate 之上并使用其运行时模型。这让 Tokio 可以<!--
-->与其他也使用 [`futures`] crate 的库进行互操作。

**注**：这个运行时模型与其他语言中的异步库非常不同<!--
-->。虽然在高级别的 API 上看起来很相似，但是代码执行的方式<!--
-->却并不相同。

## 同步模型

首先，我们来简要谈谈同步（或阻塞）模型。这是
Rust [标准库]使用的模型。

```rust
# use std::io::prelude::*;
# use std::net::TcpStream;
# fn dox(mut socket: TcpStream) {
// let socket = ……;
let mut buf = [0; 1024];
let n = socket.read(&mut buf).unwrap();

// 使用 &buf[..n];
# }
```

当调用 `socket.read` 时，要么该套接字在其接收缓冲区有待读取的数据，
要么没有。如果有待读取的数据，那么对 `read` 的调用会<!--
-->立即返回并且以相应数据填充 `buf`。而如果<!--
-->没有待读取的数据，那么 `read` 函数会阻塞当前线程直到<!--
-->收到数据。这时，会以这次新接收到的数据填充 `buf`
并且 `read` 函数会返回。

为了对多个不同的套接字并发执行读取操作，需要每个套接字<!--
-->一个线程。每个套接字使用一个线程不能很好地伸缩到<!--
-->大量的套接字。这就是所谓的 [c10k] 问题。

## 非阻塞套接字

在执行像读取这样的操作时避免阻塞线程的方法是<!--
-->不阻塞线程！当套接字的接收缓冲区中没有待读取的数据时，
`read` 函数会立即返回，表明该套接字“未<!--
-->准备好”执行读取操作。

当使用 Tokio [`TcpStream`] 时，对 `read` 的调用会立即返回<!--
-->一个值（[`ErrorKind::WouldBlock`]）即使没有待读取数据。
如果没有待读取数据，调用方负责稍后再次调用 `read`<!--
-->。其诀窍是知道什么时候是“稍后”。

考虑非阻塞读取的另一种方式是“轮询”用于读取数据的<!--
-->套接字。

## 轮询模型

对数据套接字轮询的策略可以泛化为对任何操作轮询。
例如，在轮询模型中获取“部件（widget）”的函数看起来<!--
-->类似于：

```rust,ignore
fn poll_widget() -> Async<Widget> { …… }
```

这个函数返回一个 `Async<Widget>`，其中 [`Async`] 是枚举值
`Ready(Widget)` 或 `NotReady`。[`Async`] 枚举由 [`futures`] crate 提供，
并且是轮询模型的基本要素之一。

现在，我们来定义一个无需使用这个
`poll_widget` 函数的组合子的异步任务。该任务会执行以下操作：

1. 获取一个部件。
2. 将该部件输出到标准输出（STDOUT）.
3. 结束该任务。

为了定义一个任务，我们实现了 [`Future`] trait。

```rust
# #![deny(deprecated)]
# extern crate futures;
# use futures::{Async, Future};
#
# #[derive(Debug)]
# pub struct Widget;
# fn poll_widget() -> Async<Widget> { unimplemented!() }
#
/// 轮询单个部件并将其写入到标准输出的任务。
pub struct MyTask;

impl Future for MyTask {
    // The value this future will have when ready
    type Item = ();
    type Error = ();

    fn poll(&mut self) -> Result<Async<()>, ()> {
        match poll_widget() {
            Async::Ready(widget) => {
                println!("widget={:?}", widget);
                Ok(Async::Ready(()))
            }
            Async::NotReady => {
                Ok(Async::NotReady)
            }
        }
    }
}
#
# fn main() {
# }
```

> **重要**：返回 `Async::NotReady` 具有特殊含义。关于更详细的信息，请参见<!--
> -->[下一节]。

需要注意的关键是，当调用 `MyTask::poll` 时，它会立即尝试<!--
-->获取该部件。如果对 `poll_widget` 的调用返回 `NotReady`，那么该任务<!--
-->无法取得进一步的进展。然后该任务返回 `NotReady` 本身，
表明它还没有准备好完成处理。

该任务的实现并不会阻塞。相反，“在将来的某个时刻”，
执行子会再次调用 `MyTask::poll`。会再次调用 `poll_widget`。如果
`poll_widget` 已经准备好返回一个部件，那么该任务就可以输出<!--
-->该部件了。然后可以通过返回 `Ready` 完成该任务。

## 执行子

为了使任务取得进展，必须有地方调用 `MyTask::poll`。
这就是执行子（executor）的职责。

执行子负责对任务重复调用 `poll`，直到返回 `Ready`
。有许多不同的方法可以做到这一点。例如，
[`CurrentThread`] 执行子会阻塞当前线程并循环遍历所有<!--
-->已产生的任务，并对它们轮询调用。[`ThreadPool`] 会在线程池上调度任务<!--
-->。这也是[运行时][rt]所使用的默认执行子。

所有任务**必须**都在执行子上产生，否则没有任何作用。

在最简单的情况下，执行子可能看起来类似于：

```rust
# #![deny(deprecated)]
# extern crate futures;
# use futures::{Async, Future};
# use std::collections::VecDeque;
#
pub struct SpinExecutor {
    // the tasks an executor is responsible for in
    // a double ended queue
    tasks: VecDeque<Box<Future<Item = (), Error = ()>>>,
}

impl SpinExecutor {
    pub fn spawn<T>(&mut self, task: T)
    where T: Future<Item = (), Error = ()> + 'static
    {
        self.tasks.push_back(Box::new(task));
    }

    pub fn run(&mut self) {
        while let Some(mut task) = self.tasks.pop_front() {
            match task.poll().unwrap() {
                Async::Ready(_) => {}
                Async::NotReady => {
                    self.tasks.push_back(task);
                }
            }
        }
    }
}
# pub fn main() {}
```

当然，这不会很有效率。执行子在一个繁忙的循环中自旋<!--
-->并尝试轮询所有任务，即使任务只会再次返回 `NotReady`。

理想情况下，执行子可以通过某种方式知道任务何时变更为“准备就绪”<!--
-->状态，即当对 `poll` 的调用会返回 `Ready` 时。
那么执行子看起来会类似于：

```rust
# #![deny(deprecated)]
# extern crate futures;
# use futures::{Async, Future};
# use std::collections::VecDeque;
#
# pub struct SpinExecutor {
#     ready_tasks: VecDeque<Box<Future<Item = (), Error = ()>>>,
#     not_ready_tasks: VecDeque<Box<Future<Item = (), Error = ()>>>,
# }
#
# impl SpinExecutor {
#     fn sleep_until_tasks_are_ready(&self) {}
#
    pub fn run(&mut self) {
        loop {
            while let Some(mut task) = self.ready_tasks.pop_front() {
                match task.poll().unwrap() {
                    Async::Ready(_) => {}
                    Async::NotReady => {
                        self.not_ready_tasks.push_back(task);
                    }
                }
            }

            if self.not_ready_tasks.is_empty() {
                return;
            }

            // 让线程进入休眠状态，直到有事情做
            self.sleep_until_tasks_are_ready();
        }
    }
# }
# pub fn main() {}
```

当任务从“未准备好”变成“已准备好”时能够得到通知是<!--
-->[`futures`] 任务模型的核心。我们很快会进一步深入探讨。

[`futures`]: {{< api-url "futures" >}}
[标准库]: https://doc.rust-lang.org/std/
[c10k]: https://en.wikipedia.org/wiki/C10k_problem
[`ErrorKind::WouldBlock`]: https://doc.rust-lang.org/std/io/enum.ErrorKind.html#variant.WouldBlock
[`TcpStream`]: {{< api-url "tokio" >}}/net/struct.TcpStream.html
[`Async`]: {{< api-url "futures" >}}/enum.Async.html
[`Future`]: {{< api-url "futures" >}}/future/trait.Future.html
[`CurrentThread`]: {{< api-url "tokio" >}}/executor/current_thread/index.html
[`ThreadPool`]: http://docs.rs/tokio-threadpool
[rt]: {{< api-url "tokio" >}}/runtime/index.html
[下一节]: {{< ref "/docs/getting-started/futures.md#returning-not-ready" >}}
