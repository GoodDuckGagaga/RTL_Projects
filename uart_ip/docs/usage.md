# 可配置 UART IP 使用文档

## 1. 结论：不能直接覆盖所有 UART 场景

本 IP 是可复用的“异步串口控制器内核”，适合大多数 FPGA 内部的标准 UART
收发场景，但它不是物理层芯片，也不是 Modbus、LIN、DMX512 等完整协议栈。
在普通调试串口、板间 TTL UART、带 CTS/RTS 的全双工链路和常规 9 位 UART
中可以直接使用；在 RS-485、协议专用 UART、跨时钟或高精度波特率场景中，
需要增加外围逻辑或替换部分模块。

### 1.1 场景适用性

| 使用场景 | 支持程度 | 还需要什么 |
|---|---|---|
| FPGA 调试串口、TTL UART | 直接支持 | 板级电平与引脚约束 |
| USB-UART 模块连接 | 直接支持 | 确认 1.8/2.5/3.3 V 电平兼容 |
| RS-232 | UART 内核支持 | MAX3232 等电平转换器 |
| 带 CTS/RTS 的全双工 UART | 直接支持 | 正确连接低有效 CTS/RTS |
| 9 位多机通信 | 基础帧支持 | 地址识别、静默和广播策略 |
| RS-485 半双工 | 部分支持 | 差分收发器、DE 前后保护时间、冲突处理 |
| Modbus RTU | 仅底层 UART | CRC、地址、超时、T1.5/T3.5、RS-485 控制 |
| LIN | 部分支持 | 精确 Break/Delimiter、Sync、自动波特率、校验和 |
| DMX512 | 部分支持 | 精确 Break/MAB 时序、方向与协议状态机 |
| MIDI | 仅 UART 字节层 | 31.25 kbaud 校验、光耦物理层、MIDI 协议 |
| XON/XOFF 软件流控 | UART 可承载 | 软件或上层协议识别控制字符 |
| IrDA、ISO 7816 智能卡 | 不直接支持 | 脉冲整形、单线双向、电气与专用时序模块 |
| 同步 USART/SPI 模式 | 不支持 | 独立同步串行控制器 |
| TX/RX 不同波特率 | 不支持 | 为 TX/RX 配置独立节拍器 |
| 跨时钟域数据接口 | 不直接支持 | 异步 FIFO 或 CDC 桥 |

## 2. 主要不足与风险边界

### 2.1 整数波特率分频

当前 `uart_tick_gen` 使用整数分频，TX 与 RX 共用一个过采样节拍。它没有小数
NCO、自动波特率检测或运行时误差补偿。当系统时钟不能整除目标波特率与过采
样倍数的乘积时，会产生固定误差。

```text
divisor = round(CLK_HZ / (baud * OVERSAMPLE))
actual_baud = CLK_HZ / (divisor * OVERSAMPLE)
error_percent = (actual_baud / baud - 1) * 100
```

示例：

| 时钟 | 过采样 | 目标波特率 | divisor | 实际波特率 | 误差 |
|---:|---:|---:|---:|---:|---:|
| 50 MHz | 16 | 9,600 | 326 | 9,585.89 | -0.147% |
| 50 MHz | 16 | 115,200 | 27 | 115,740.74 | +0.469% |
| 100 MHz | 16 | 115,200 | 54 | 115,740.74 | +0.469% |
| 50 MHz | 16 | 1,000,000 | 3 | 1,041,666.67 | +4.167% |

最后一行通常不建议直接使用。工程中应同时考虑本端、对端晶振误差和帧长度；
常规设计可把单端误差控制在约 1% 以内，但最终容限必须依据对端采样器和协议
要求确定。误差不满足时，应更换系统时钟、降低过采样倍数或把节拍器替换为
小数累加器。

### 2.2 RS-485 方向时序不完整

`tx_de_o` 在发送器开始输出起始位时拉高，在最后一个停止位完成时拉低，没有
可配置的 DE 提前时间和保持时间。某些 RS-485 收发器需要 DE 先于起始位建立，
并在停止位后继续保持一段时间。这类系统应在 `uart_core` 外增加方向控制状态
机，不应无条件把 `tx_de_o` 直接接到收发器 DE。

### 2.3 Break 检测是实用型判定，不是协议级计时器

接收器把“数据全零且停止位为低”的帧判为 Break，然后等待线路恢复为高。
这种判定适合通用 UART 错误识别，但不能测量 Break 的精确持续时间，也可能把
全零数据加错误停止位识别为 Break。LIN、DMX512 等协议应增加独立低电平计时器
和协议规定的 delimiter/MAB 检查。

### 2.4 FIFO 和数据接口只支持单时钟域

TX/RX FIFO 都使用 `clk_i`，所有 ready/valid 数据接口也必须属于该时钟域。
如果处理器总线、DMA 或数据源使用其他时钟，需要在 IP 外放置异步 FIFO。
当前 16 深度参考配置映射到 LUTRAM；很深的 FIFO 建议改为同步读结构以便使用
Block RAM。

### 2.5 配置是全局且按空闲边界更新

TX 与 RX 共用波特率和帧格式。只有 TX FIFO 为空、TX/RX 引擎空闲、RX 为高且
没有 Break 时，`cfg_ready_o` 才会有效。因此不能为 FIFO 中的每个字节附带不
同格式，也不能在收发过程中立即改变格式。需要逐字节格式时，应把配置字段与
TX 数据一起存入 FIFO，并给 RX/TX 分别锁存配置。

### 2.6 物理层和协议层不在本 IP 内

本 IP 输出的是 FPGA 逻辑电平 UART 信号，不包含：

- RS-232 正负电压转换、RS-485 差分驱动和终端匹配；
- ESD、防浪涌、隔离和电平转换；
- CRC、地址、重试、超时、包格式和命令解析；
- DTR、DSR、DCD、RI 等完整 Modem 控制线；
- 自动方向、总线冲突检测和多主仲裁。

### 2.7 验证与时序结果不是所有器件的保证

当前自检覆盖 8E1、7O2、9 位 mark parity、CTS、环回和 Break。尚未包含大规模
随机噪声、所有配置排列、形式验证、门级时序仿真和长期亚稳态统计。Vivado
2018.3 的 `+1.798 ns` WNS 只对应 `xc7a35tcpg236-1`、默认参数、100 MHz 和
脚本中的内部时钟约束；更换器件、参数、引脚或 XDC 后必须重新签核。

## 3. 文件与模块

| 文件 | 用途 |
|---|---|
| `rtl/uart_core.sv` | 顶层、配置、同步器、FIFO 与流控整合 |
| `rtl/uart_tick_gen.sv` | 整数过采样节拍器 |
| `rtl/uart_tx_engine.sv` | TX 帧状态机 |
| `rtl/uart_rx_engine.sv` | RX 过采样、表决和错误检测 |
| `rtl/uart_fifo.sv` | 可参数化同步 FIFO |
| `tb/tb_uart_core.sv` | 自检测试平台 |
| `scripts/run_iverilog.ps1` | Icarus 编译与仿真 |
| `scripts/synth_vivado.tcl` | Vivado 2018.3 实现检查 |
| `docs/design.md` | 架构设计方案 |

## 4. 编译期参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `CLK_HZ` | 50,000,000 | 系统时钟频率，用于复位默认分频值 |
| `DEFAULT_BAUD` | 115,200 | 复位后的默认波特率 |
| `OVERSAMPLE` | 16 | RX 过采样倍数；使用偶数，推荐 8 或 16 |
| `DIV_WIDTH` | 24 | 过采样分频计数器宽度 |
| `TX_FIFO_DEPTH` | 16 | TX FIFO 深度，要求至少 2 |
| `RX_FIFO_DEPTH` | 16 | RX FIFO 深度，要求至少 2 |
| `RTS_MARGIN` | 2 | RX FIFO 剩余此数量时撤销 RTS |
| `DEFAULT_DATA_BITS` | 8 | 复位后的数据位数 |
| `DEFAULT_PARITY` | 0 | 复位后的校验方式 |
| `DEFAULT_STOP_BITS` | 1 | 复位后的停止位数 |

较低波特率需要更宽的 `DIV_WIDTH`。可表示的最低波特率近似为：

```text
CLK_HZ / ((2^DIV_WIDTH - 1) * OVERSAMPLE)
```

由于分频值最小被限制为 2，可表示的最高波特率近似为：

```text
CLK_HZ / (2 * OVERSAMPLE)
```

## 5. 顶层接口

### 5.1 时钟与复位

| 信号 | 方向 | 说明 |
|---|---|---|
| `clk_i` | 输入 | 所有逻辑、FIFO 和数据接口的时钟 |
| `rst_n_i` | 输入 | 低有效异步复位 |

建议在系统顶层异步拉低复位、同步释放复位。释放后至少等待两个 `clk_i` 周期，
让 RX 和 CTS 两级同步器建立稳定状态。

### 5.2 运行时配置接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `cfg_valid_i` | 输入 | 配置请求有效 |
| `cfg_ready_o` | 输出 | 当前处于安全配置边界 |
| `cfg_applied_o` | 输出 | 配置被接受的单周期脉冲 |
| `cfg_baud_divisor_i` | 输入 | 每个过采样 tick 的系统时钟周期数，最小为 2 |
| `cfg_data_bits_i` | 输入 | 5～9；非法值会被限制到边界 |
| `cfg_parity_i` | 输入 | 0 无、1 偶、2 奇、3 mark、4 space |
| `cfg_stop_bits_i` | 输入 | 2 表示两位，其余值表示一位 |
| `cfg_flow_control_i` | 输入 | 使能低有效 CTS/RTS 流控 |
| `cfg_loopback_i` | 输入 | 把内部 TX 线路送回 RX 同步器 |

配置源必须保持所有配置字段和 `cfg_valid_i`，直到出现
`cfg_valid_i && cfg_ready_o`。握手完成后应在下一周期撤销 `cfg_valid_i`。

### 5.3 TX 接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `tx_valid_i` | 输入 | `tx_data_i` 有效 |
| `tx_ready_o` | 输出 | TX FIFO 可接受数据 |
| `tx_data_i[8:0]` | 输入 | 待发送数据；未使用的高位被忽略 |
| `tx_break_i` | 输入 | 请求持续发送低电平 Break |
| `tx_flush_i` | 输入 | 清空尚未发送的 TX FIFO，不终止当前帧 |
| `tx_o` | 输出 | UART 串行输出，空闲为高 |
| `tx_de_o` | 输出 | 简单 RS-485 方向提示，无前后保护时间 |
| `tx_busy_o` | 输出 | 引擎活动、FIFO 非空或 Break 时为高 |
| `tx_done_o` | 输出 | 每帧完成时脉冲一个 `clk_i` 周期 |
| `tx_level_o` | 输出 | TX FIFO 当前条目数 |

只有在 `tx_valid_i && tx_ready_o` 的时钟沿，数据才进入 FIFO。`tx_break_i`
不会截断正在发送的帧；当前帧结束后线路才保持低电平。

### 5.4 RX 接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `rx_i` | 输入 | 异步 UART 输入，空闲为高 |
| `rx_valid_o` | 输出 | RX FIFO 首条数据有效 |
| `rx_ready_i` | 输入 | 下游准备取走当前数据 |
| `rx_data_o[8:0]` | 输出 | 当前 RX FIFO 数据 |
| `rx_parity_error_o` | 输出 | 当前数据的校验错误 |
| `rx_framing_error_o` | 输出 | 当前数据的停止位错误 |
| `rx_break_o` | 输出 | 当前数据被判定为 Break |
| `rx_flush_i` | 输入 | 清空 RX FIFO，并清除 overrun；不终止当前帧 |
| `clear_errors_i` | 输入 | 清除粘滞的 `rx_overrun_o` |
| `rx_overrun_o` | 输出 | RX FIFO 曾发生溢出，清除前保持为高 |
| `rx_busy_o` | 输出 | 正在接收或等待 Break 释放 |
| `rx_level_o` | 输出 | RX FIFO 当前条目数 |

`rx_data_o` 和三个逐条目错误标志只在 `rx_valid_o=1` 时有意义。数据在
`rx_valid_o && rx_ready_i` 的时钟沿弹出。

### 5.5 硬件流控

| 信号 | 方向 | 有效电平 | 说明 |
|---|---|---|---|
| `cts_n_i` | 输入 | 低 | 对端允许本端开始下一帧 |
| `rts_n_o` | 输出 | 低 | 本端 RX FIFO 尚有足够空间 |

CTS 只阻止新帧开始，不截断已发送帧。RX FIFO 达到
`RX_FIFO_DEPTH-RTS_MARGIN` 后 `rts_n_o` 拉高。禁用流控时 `rts_n_o`
保持低，`cts_n_i` 被忽略。

## 6. 典型实例化

下面示例为 100 MHz 系统时钟、16 倍过采样和 16 深度 FIFO：

```systemverilog
localparam integer UART_DIV_WIDTH = 24;

logic [4:0] tx_level;
logic [4:0] rx_level;

uart_core #(
    .CLK_HZ            (100_000_000),
    .DEFAULT_BAUD      (115_200),
    .OVERSAMPLE        (16),
    .DIV_WIDTH         (UART_DIV_WIDTH),
    .TX_FIFO_DEPTH     (16),
    .RX_FIFO_DEPTH     (16),
    .RTS_MARGIN        (2),
    .DEFAULT_DATA_BITS (4'd8),
    .DEFAULT_PARITY    (3'd0),
    .DEFAULT_STOP_BITS (2'd1)
) u_uart (
    .clk_i                  (clk),
    .rst_n_i                (rst_n),

    .cfg_valid_i            (cfg_valid),
    .cfg_ready_o            (cfg_ready),
    .cfg_baud_divisor_i     (cfg_divisor),
    .cfg_data_bits_i        (cfg_data_bits),
    .cfg_parity_i           (cfg_parity),
    .cfg_stop_bits_i        (cfg_stop_bits),
    .cfg_flow_control_i     (cfg_flow_control),
    .cfg_loopback_i         (cfg_loopback),
    .cfg_applied_o          (cfg_applied),

    .tx_valid_i             (tx_valid),
    .tx_ready_o             (tx_ready),
    .tx_data_i              (tx_data),
    .tx_break_i             (tx_break),
    .tx_flush_i             (tx_flush),
    .tx_o                   (uart_tx),
    .tx_de_o                (uart_tx_de),
    .tx_busy_o              (tx_busy),
    .tx_done_o              (tx_done),
    .tx_level_o             (tx_level),

    .rx_i                   (uart_rx),
    .rx_ready_i             (rx_ready),
    .rx_valid_o             (rx_valid),
    .rx_data_o              (rx_data),
    .rx_parity_error_o      (rx_parity_error),
    .rx_framing_error_o     (rx_framing_error),
    .rx_break_o             (rx_break),
    .rx_flush_i             (rx_flush),
    .clear_errors_i         (clear_errors),
    .rx_overrun_o           (rx_overrun),
    .rx_busy_o              (rx_busy),
    .rx_level_o             (rx_level),

    .cts_n_i                (uart_cts_n),
    .rts_n_o                (uart_rts_n)
);
```

未使用硬件流控时，把 `cfg_flow_control_i` 配为 0，`cts_n_i` 可固定为 0。

## 7. 推荐操作顺序

### 7.1 上电和配置

1. 拉低 `rst_n_i`，保持 RX 线路处于空闲高电平。
2. 同步释放复位并等待至少两个时钟周期。
3. 计算波特率 divisor。
4. 设置所有 `cfg_*` 字段并拉高 `cfg_valid_i`。
5. 等待 `cfg_ready_o=1` 的时钟沿完成握手。
6. 撤销 `cfg_valid_i`；可用 `cfg_applied_o` 记录配置完成。

配置 100 MHz、115200、16 倍过采样、8N1 时：

```systemverilog
cfg_baud_divisor_i = 24'd54;
cfg_data_bits_i    = 4'd8;
cfg_parity_i       = 3'd0;
cfg_stop_bits_i    = 2'd1;
```

### 7.2 发送数据

1. 等待 `tx_ready_o=1`。
2. 驱动 `tx_data_i` 和 `tx_valid_i=1`。
3. 在握手时钟沿后撤销 `tx_valid_i`。
4. 可继续写 FIFO；若需确认线路发送结束，等待 FIFO 空且 `tx_busy_o=0`。

注意：`tx_done_o` 只代表一帧完成，不代表 FIFO 中所有帧都完成。

### 7.3 接收数据

1. 等待 `rx_valid_o=1`。
2. 同时读取 `rx_data_o`、parity/framing/break 标志。
3. 准备好消费时拉高 `rx_ready_i`。
4. 在 `rx_valid_o && rx_ready_i` 的时钟沿后完成弹出。
5. 定期检查 `rx_overrun_o`；出现后应评估 FIFO 深度和服务延迟。

## 8. 特殊场景集成

### 8.1 RS-485 半双工

推荐在外部增加状态机：

```text
IDLE
  -> 拉高外部 DE
  -> 等待 transceiver_de_setup
  -> 允许数据写入 UART
  -> 等待 tx_level_o==0 且 tx_busy_o==0
  -> 等待 transceiver_de_hold
  -> 拉低外部 DE
  -> 返回 IDLE
```

接收期间关闭驱动器，必要时忽略本机发送回波。Modbus RTU 还需在外部实现
CRC16 和 1.5/3.5 字符静默计时。

### 8.2 9 位多机 UART

把 `cfg_data_bits_i` 配为 9，上层可把第 9 位作为地址/数据标记。但本 IP 不会
自动筛选地址；地址匹配、节点静默和广播处理应在 RX ready/valid 接口之后实现。

### 8.3 LIN 或 DMX512 Break

发送端可通过保持 `tx_break_i` 产生低电平，但必须由外部计时器控制低电平和
后续高电平 delimiter/MAB 的精确宽度。接收端如需协议合规，应另外测量 RX
连续低电平和恢复高电平时间，而不是只依赖 `rx_break_o`。

### 8.4 跨时钟或处理器总线

不要把其他时钟域的 valid/ready 信号直接接入。可在 UART 与 AXI/APB/Wishbone
包装器之间加入异步 FIFO，或让总线包装器本身运行在 `clk_i` 下。寄存器映射、
中断、水位阈值和 DMA 均属于包装层功能。

## 9. 仿真与 Vivado 检查

在 `uart_ip` 目录运行自检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_iverilog.ps1
```

预期输出：

```text
PASS: configurable UART self-check completed
```

使用当前机器上的 Vivado 2018.3：

```powershell
& 'D:\vivado18\Vivado\2018.3\bin\vivado.bat' -mode batch `
  -source .\scripts\synth_vivado.tcl -nojournal -nolog
```

脚本在 `build/vivado` 生成利用率报告、时序报告和 routed checkpoint。`build`
目录已被 `.gitignore` 排除。

## 10. 项目集成检查表

- [ ] 目标波特率误差已计算并满足对端要求。
- [ ] `OVERSAMPLE`、`DIV_WIDTH` 和 FIFO 深度适合目标场景。
- [ ] RX、TX、CTS、RTS 的有效电平与板级器件一致。
- [ ] RS-232/RS-485 等场景已加入正确物理层。
- [ ] RS-485 DE 前后保护时间由外部状态机满足。
- [ ] 异步 RX/CTS 已纳入 CDC 检查，复位释放已同步处理。
- [ ] 跨时钟数据路径已使用异步 FIFO 或可靠 CDC。
- [ ] RX FIFO 最坏服务延迟不会导致 overrun。
- [ ] 实际器件、引脚和完整 XDC 下已重新运行实现与时序签核。
- [ ] 协议层 CRC、超时、地址和重试逻辑已单独验证。
- [ ] 已针对目标波特率、帧格式、噪声和错误注入扩充测试。

## 11. 建议的后续增强

若希望覆盖更多场景，建议按优先级增加：

1. 小数 NCO 波特率发生器和运行时误差计算。
2. 独立 TX/RX 波特率与帧格式。
3. 可配置 Break 低电平计数器与 delimiter 检查。
4. RS-485 DE 提前/保持计时和冲突检测。
5. 可选异步 FIFO、AXI-Lite/APB 寄存器包装器和中断控制器。
6. 每字节配置标签、9 位地址过滤和多机模式。
7. 自动波特率、极性反转和 1.5 停止位。
8. 随机约束验证、断言、形式验证和错误注入回归。
