# 可配置高时序性能 UART IP 设计方案

## 1. 目标与适用场景

本 IP 面向 FPGA 内部控制口、板间低速链路、调试串口、RS-232/RS-485、
多机 9 位地址帧以及需要硬件流控的持续数据流。设计目标如下：

1. 同一套 RTL 覆盖 5～9 数据位、五种校验、1/2 停止位和多种波特率。
2. TX/RX 完全独立，使用 ready/valid 接口与 FIFO 隔离软件或上游逻辑抖动。
3. RX 对异步输入进行同步，并使用过采样中心三点多数表决提高抗干扰能力。
4. 将串行输出、状态和关键控制全部寄存，减少组合逻辑深度并提高 Fmax。
5. 配置只在安全空闲边界更新，每一帧开始时再次锁存，避免半帧参数改变。

## 2. 总体架构

```text
                    +---------------- Configuration ----------------+
                    | divisor / data / parity / stop / flow / loop |
                    +-------------------------+---------------------+
                                              |
 ready/valid -> TX FIFO -> TX engine -> registered TX -----> tx_o
                                  |                 +------> tx_de_o
                                  |                 |
                                  +---- loopback ---+
                                                       asynchronous
 rx_i -> 2-FF synchronizer -> RX engine -> RX FIFO -> ready/valid
                               | 3-point vote          + error flags

 cts_n_i -> 2-FF synchronizer -> frame-start gate
 RX FIFO fill level -------------------------------> rts_n_o
```

模块划分：

- `uart_tick_gen`：产生 RX/TX 共用的过采样节拍。
- `uart_tx_engine`：生成起始位、数据位、可选校验位和停止位。
- `uart_rx_engine`：完成起始位确认、三点表决、移位接收及错误判断。
- `uart_fifo`：同步单时钟 FIFO；支持非 2 的幂深度和同周期 push/pop。
- `uart_core`：配置管理、输入同步、FIFO、流控、环回及顶层状态整合。

## 3. 配置方案

### 3.1 编译期参数

| 参数 | 含义 | 默认值 |
|---|---|---:|
| `CLK_HZ` | 系统时钟频率 | 50 MHz |
| `DEFAULT_BAUD` | 复位后的波特率 | 115200 |
| `OVERSAMPLE` | RX 过采样倍数，建议 8 或 16 | 16 |
| `DIV_WIDTH` | 波特率分频器宽度 | 24 |
| `TX_FIFO_DEPTH` | TX FIFO 深度，要求至少 2 | 16 |
| `RX_FIFO_DEPTH` | RX FIFO 深度，要求至少 2 | 16 |
| `RTS_MARGIN` | RTS 提前停止接收的余量 | 2 |

### 3.2 运行期配置

`cfg_valid_i && cfg_ready_o` 时接受新配置，并产生一个周期的
`cfg_applied_o`。`cfg_ready_o` 仅在以下条件同时成立时拉高：

- TX 引擎空闲且 TX FIFO 为空；
- RX 引擎空闲且同步后的 RX 为高电平；
- 当前没有发送 Break。

因此，配置不会切断正在传输或接收的帧。数据位被限制在 5～9；非法校验值
回退到无校验；停止位除 2 外均按 1 处理；分频值最小为 2。

整数分频公式：

```text
divisor = round(CLK_HZ / (baud * OVERSAMPLE))
actual_baud = CLK_HZ / (divisor * OVERSAMPLE)
error = (actual_baud / baud - 1) * 100%
```

系统集成时应使本端与对端的总采样误差留有余量；工程上通常建议单端误差不
超过约 1%，并优先使用 16 倍过采样。

## 4. TX 数据通路

上游以 `tx_valid_i/tx_ready_o` 写入 9 位 TX FIFO。发送器仅在空闲时读取
一个条目，并锁存当前帧格式。若启用流控，只有同步后的 `cts_n_i=0` 才开始
新帧；已开始的帧不会被 CTS 截断。

发送顺序为：起始位 0、LSB first 数据、可选校验、1/2 个停止位 1。
`tx_o` 是寄存器输出。`tx_done_o` 在一帧最后一个停止位完成时脉冲一个时钟。
`tx_break_i` 不会破坏正在发送的帧，而是在帧结束后把线路保持为低；期间新
数据仍可进入 FIFO。`tx_de_o` 在正常发送或 Break 期间有效，可直接用于
RS-485 驱动器方向控制；如外部收发器要求前后保护时间，应在系统顶层增加
可参数化延时层。

## 5. RX 数据通路

`rx_i` 先通过两级触发器同步。RX 检测低电平后，在每一位中心附近的三个
过采样点投票：

```text
OVERSAMPLE/2 - 1, OVERSAMPLE/2, OVERSAMPLE/2 + 1
```

至少两个采样为 1 时判为 1。起始位表决失败会被当作毛刺丢弃。接收结果连同
校验错误、帧错误和 Break 标志一起写入 RX FIFO，因此错误状态与对应数据不
会错位。RX FIFO 满时的新帧被丢弃，并置位粘滞的 `rx_overrun_o`；软件通过
`clear_errors_i` 清除。

当停止位为低且接收数据全零时，IP 报告一次 Break，并等待线路恢复为高后再
启动下一次接收，避免持续低电平产生大量伪帧。

## 6. 流控与缓冲

- CTS 为低有效，只阻止“下一帧开始”，不会截断当前帧。
- RTS 为低表示可继续接收；RX FIFO 达到 `DEPTH-RTS_MARGIN` 时拉高。
- FIFO 支持同周期读取和写入，在满且同时 pop/push 时不会误报溢出。
- `tx_flush_i`、`rx_flush_i` 用于丢弃各自 FIFO 中尚未处理的数据。

## 7. 时序性能策略

1. TX 串行输出完全寄存，状态译码不直接形成长组合输出路径。
2. RX 每位只使用 2 位投票计数器；校验 XOR 最多覆盖 9 位。
3. 波特率计数器宽度参数化，避免为低速应用之外的无效位付出面积和时延。
4. FIFO 指针采用显式回绕，兼容任意深度；数据输出为首字直出以减少一周期
   控制延迟。
5. 异步 RX/CTS 各自使用两级同步器，所有其余接口与 `clk_i` 同步。
6. 运行时配置先集中寄存，再在帧开始锁存，配置总线不参与逐位关键路径。

若目标频率很高，可进一步把大深度 FIFO 映射为 Block RAM、缩小
`DIV_WIDTH`、将 TX/RX 使用不同节拍器，或在综合约束中把同步器标记为
`ASYNC_REG`。本版本保持纯 RTL 和跨 FPGA 厂商可移植性，因此未写入厂商属性。

### 7.1 Vivado 2018.3 参考结果

使用随附脚本、默认 IP 参数、`xc7a35tcpg236-1` 和 100 MHz 时钟完成布局布线：

| 指标 | 结果 |
|---|---:|
| Slice LUT | 227 |
| Slice Register | 177 |
| LUT as Memory | 16 |
| Block RAM | 0 |
| WNS | +1.798 ns |
| TNS | 0 ns |

该结果只证明当前参考器件上的 100 MHz 内部时序收敛。最终工程仍需使用实际
器件、引脚、I/O delay、板级时钟和完整 XDC 重新签核。

## 8. 验证方案

自检测试平台覆盖：

- 8E1 内部环回；
- 7O2 引脚级环回；
- 9 位数据加 mark parity；
- CTS 阻塞及恢复；
- TX Break 与 RX Break/帧错误识别；
- FIFO 基本握手及无意外 overrun。

后续项目级验证建议补充随机帧格式、±2% 两端波特率偏差、输入毛刺、FIFO
满/空并发、异步复位释放、形式验证以及目标器件布局布线后的时序仿真。

## 9. 已知边界

- 本版使用整数分频，不包含自动波特率检测和小数 NCO；需要更低误差时可替换
  `uart_tick_gen`，其余模块接口无需改变。
- 数据与控制 ready/valid 接口必须与 `clk_i` 同步；跨时钟数据应在 IP 外部使用
  异步 FIFO。
- FIFO 深度应不小于 2。
- `OVERSAMPLE` 应使用偶数，推荐 8 或 16。
