# OPPO 互联与 TUN 冲突修复工具

适用于 Windows 的手动 PowerShell 工具。针对 OPPO 互联开启物理联网网卡的 IPv4 转发后，Clash / Mihomo 系代理客户端开启 TUN 就断网的情况，关闭选定网卡的转发并验证状态。

## 下载与使用

从仓库页面选择 **Code → Download ZIP**，解压整个文件夹后运行。请将 `.cmd` 文件与 `Fix-OppoTun.ps1` 保留在同一目录。

1. 如果开启 TUN 已经断网，先在代理客户端关闭 TUN，并启用系统代理恢复上网。
2. 打开 OPPO 互联，连接好常用设备。
3. 双击 **修复.cmd**，在 Windows 管理员确认窗口中选择“是”。
4. 工具列出物理网卡及当前 IPv4 转发状态。只有一张候选网卡时会选中它，多张时输入实际联网网卡的接口编号。
5. 核对网卡名称和修改内容，输入 `Y` 执行。已处于 `Disabled` 状态的网卡会直接显示当前状态。
6. 显示完成后，开启代理客户端的 TUN，分别验证国内外网站，以及 OPPO 的投屏、文件传输或 USB 连接。

脚本显示完成，代表网卡转发状态已核验。实际联网效果需要按第 6 步检查。

## 功能

### 手动修复

`修复.cmd` 以管理员权限启动脚本，将选定物理网卡的 **IPv4 Forwarding** 设置为 `Disabled`。操作仅写入 Windows 的 `ActiveStore`，适合发生故障时手动运行。

### 通用网卡选择

通过 Windows `Get-NetAdapter -Physical` 枚举物理网卡，交互模式列出当前已连接的候选项。支持被 Windows 识别为物理网卡的以太网、Wi-Fi 和部分 USB 网卡。

列表显示接口编号、网卡名称、硬件描述、IPv4 转发状态，并标记存在 IPv4 默认路由的接口。多网卡同时联网时，由使用者选择实际出口。默认路由标记用来辅助判断。

网卡选择完成后，脚本在写入前再次比对接口编号和 GUID，避免设备重建时修改到另一张网卡。发布版在运行时读取 GUID，适用于不同电脑。

### 查看状态

`查看状态.cmd` 列出联网物理网卡及转发状态。也可以用命令行指定某张物理网卡进行检查。

### 恢复转发

`恢复转发.cmd` 将选定网卡的 IPv4 转发设为 `Enabled`。它用于重新启用依赖转发的功能。该入口会要求确认，并提示先关闭 TUN，因为重新开启转发可能让原故障复发。

恢复入口执行明确的“开启转发”操作，原始状态需要使用者根据实际网络用途判断。

### 权限与运行方式

修改时通过 Windows 标准 UAC 请求管理员权限。工具运行一次后退出，使用方式为手动按需启动。网卡状态已经符合目标时，重复运行会显示当前状态。

## 修复原理

在本项目起源的排障案例中，OPPO 互联后台服务创建 `vgate0` 后，日志记录了对物理联网网卡执行 `enable_ip_forwarding`。此时开启 FlClash TUN，国内外 HTTPS 请求均超时。关闭物理出口网卡的 IPv4 转发后，TUN 联网恢复。

社区还有记录了 `reject loopback connection` 的对照测试。在这类环境下，开启转发会与 TUN 自动路由产生冲突，使内核的出站连接可能重新进入 TUN。该机制是社区排查结论，具体环境仍应结合本机日志和测试确认。[社区排查记录](https://github.com/clash-verge-rev/clash-verge-rev/issues/8117)

核心操作如下，网卡名称应替换为实际联网接口。

```powershell
Set-NetIPInterface -InterfaceAlias "以太网" `
  -AddressFamily IPv4 `
  -Forwarding Disabled `
  -PolicyStore ActiveStore
```

`Forwarding` 控制网卡是否转发到达该接口的数据包，`ActiveStore` 保存当前运行配置，系统重启后会重新建立活动配置。OPPO 或其他程序也可能在运行期间再次开启转发。[Microsoft 参数文档](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface)

## 适用范围与已验证情况

- 目标平台为 Windows 10 / 11，使用系统自带的 Windows PowerShell 5.1，以及 `NetAdapter`、`NetTCPIP` 模块。
- 原始案例使用 FlClash 0.9.1、Realtek 有线网卡和 OPPO 互联。关闭转发后，绕过系统代理的国内 HTTPS 测试返回 200，海外连通性测试返回 204。
- 原始案例中，OPPO 两个后台服务继续运行，使用者确认常用互联功能正常。
- 通用版沿用同一条网卡设置命令，并增加网卡选择、状态查看和恢复入口。不同 Wi-Fi、USB 网卡、Windows 版本及互联功能组合需要各自验证。

Clash Verge Rev 和 FlClash 社区均报告过 OPPO 互联与 TUN 的相关冲突，可用作排查线索。[Clash Verge 讨论](https://github.com/clash-verge-rev/clash-verge-rev/discussions/6712) · [FlClash 问题记录](https://github.com/chen08209/FlClash/issues/1957)

## 使用限制

- 关闭转发可能影响依赖所选网卡的 Internet 连接共享、移动热点、路由或其他转发功能。实际影响取决于网络拓扑和使用方式。
- OPPO 启动、服务重启、设备重连或电脑重启后，状态可能变化。故障复发时先查看状态，再按需运行修复。
- 脚本针对“物理出口 IPv4 转发开启”这一类冲突。如果转发本来已关闭而 TUN 仍无法联网，需要继续检查内核日志、DNS、出口路由和客户端设置。
- 若正在通过远程桌面或其他远程连接处理网络，应预先准备本地操作方式，以便连接受影响时恢复。
- 脚本保持使用系统现有的执行策略。如果下载文件被 Windows 阻止，请核对来源和代码后，在文件属性中按系统提示解除阻止。组织管理的电脑应遵循本机管理策略。

## 命令行用法

先查看网卡编号。

```powershell
powershell.exe -NoProfile -File .\Fix-OppoTun.ps1 -Action Status
```

指定物理网卡进行修复，仍会显示修改确认。

```powershell
powershell.exe -NoProfile -File .\Fix-OppoTun.ps1 -Action Fix -InterfaceIndex 6
```

重新开启该接口的转发前，先关闭 TUN。

```powershell
powershell.exe -NoProfile -File .\Fix-OppoTun.ps1 -Action Restore -InterfaceIndex 6
```

`-NoPause` 用于跳过结束时的“按回车关闭”，例如读取状态。

```powershell
powershell.exe -NoProfile -File .\Fix-OppoTun.ps1 -Action Status -NoPause
```

## 问题反馈

反馈时请附 Windows 和代理客户端版本、联网方式、网卡转发修改前后的状态、错误提示，以及 OPPO 的连接方式和受影响功能。分享日志前请移除订阅地址、节点密码、访问令牌及个人设备信息。
