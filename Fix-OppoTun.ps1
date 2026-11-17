param(
    [ValidateSet('Fix', 'Restore', 'Status')]
    [string]$Action = 'Fix',
    [ValidateRange(0, 2147483647)]
    [int]$InterfaceIndex = 0,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$exitCode = 0

function Wait-BeforeExit {
    if (-not $NoPause) {
        [void](Read-Host '按回车关闭窗口')
    }
}

# 修改网卡需要 Windows 管理员权限。只传递经过验证的动作和接口编号。
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($Action -ne 'Status' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $arguments = '-NoProfile -File "{0}" -Action {1} -InterfaceIndex {2}' -f $PSCommandPath, $Action, $InterfaceIndex
        if ($NoPause) { $arguments += ' -NoPause' }
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -PassThru -Wait
        exit $process.ExitCode
    } catch {
        Write-Host ('管理员启动失败或确认已取消。{0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Wait-BeforeExit
        exit 1
    }
}

try {
    Import-Module NetAdapter
    Import-Module NetTCPIP

    $physicalAdapters = @(Get-NetAdapter -Physical)
    if ($InterfaceIndex -gt 0) {
        $adapters = @($physicalAdapters | Where-Object { $_.ifIndex -eq $InterfaceIndex })
        if ($adapters.Count -ne 1) {
            throw '指定接口未被 Windows 识别为物理网卡。请先运行查看状态.cmd 核对编号。'
        }
    } else {
        $adapters = @($physicalAdapters | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex)
    }
    if ($adapters.Count -eq 0) {
        throw '没有找到已连接的物理网卡。请检查以太网或 Wi-Fi 连接。'
    }

    $defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
    Write-Host 'OPPO 互联 / TUN 网卡转发修复' -ForegroundColor Cyan
    Write-Host ''
    foreach ($adapter in $adapters) {
        $ip = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore
        $routeNote = ''
        if ($defaultRoutes.InterfaceIndex -contains $adapter.ifIndex) { $routeNote = '，存在 IPv4 默认路由' }
        Write-Host ('[{0}] {1} | {2} | IPv4 转发 {3}{4}' -f $adapter.ifIndex, $adapter.Name, $adapter.InterfaceDescription, $ip.Forwarding, $routeNote)
    }

    if ($Action -ne 'Status') {
        if ($adapters.Count -eq 1) {
            $selected = $adapters[0]
        } else {
            $answer = Read-Host '输入实际联网网卡的方括号编号，输入 Q 取消'
            if ($answer -eq 'Q') { return }
            $selectedIndex = 0
            if (-not [int]::TryParse($answer, [ref]$selectedIndex)) { throw '请输入列表中的数字编号。' }
            $matches = @($adapters | Where-Object { $_.ifIndex -eq $selectedIndex })
            if ($matches.Count -ne 1) { throw '选择的编号不在候选列表中。' }
            $selected = $matches[0]
        }

        $desiredState = 'Disabled'
        if ($Action -eq 'Restore') { $desiredState = 'Enabled' }
        $before = Get-NetIPInterface -InterfaceIndex $selected.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore

        if ($before.Forwarding.ToString() -eq $desiredState) {
            Write-Host ('{0} 的 IPv4 转发已是 {1}。' -f $selected.Name, $desiredState) -ForegroundColor Green
        } else {
            Write-Host ''
            Write-Host ('目标网卡：{0}，接口编号 {1}' -f $selected.Name, $selected.ifIndex)
            Write-Host ('IPv4 转发将从 {0} 改为 {1}，仅写入 ActiveStore。' -f $before.Forwarding, $desiredState)
            if ($Action -eq 'Fix') {
                Write-Host '关闭转发可能影响依赖此网卡的网络共享、热点或路由功能。'
            } else {
                Write-Host '重新开启转发可能再次触发 TUN 断网。请先关闭 TUN。'
            }
            $confirmation = Read-Host '确认请输入 Y，其他输入取消'
            if ($confirmation -eq 'Y') {
                # 用户选择后再次核对 GUID，防止等待期间网卡重建导致编号被复用。
                $current = @(Get-NetAdapter -Physical | Where-Object { $_.ifIndex -eq $selected.ifIndex })
                if ($current.Count -ne 1 -or $current[0].InterfaceGuid -ne $selected.InterfaceGuid) {
                    throw '网卡已变化，请重新运行并选择网卡。'
                }
                Set-NetIPInterface -InterfaceIndex $selected.ifIndex -AddressFamily IPv4 -Forwarding $desiredState -PolicyStore ActiveStore
                $after = Get-NetIPInterface -InterfaceIndex $selected.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore
                if ($after.Forwarding.ToString() -ne $desiredState) { throw '修改后状态校验失败，可能被其他程序重新设置。' }
                Write-Host ('已完成，当前 IPv4 转发为 {0}。' -f $after.Forwarding) -ForegroundColor Green
            } else {
                Write-Host '已取消。'
            }
        }
        Write-Host '网卡状态校验完成后，请分别验证 TUN 联网和常用的互联功能。'
        Write-Host '重启、OPPO 服务重启或设备重连后，若问题复发，可再次手动运行。'
    }
} catch {
    Write-Host ('执行失败：{0}' -f $_.Exception.Message) -ForegroundColor Red
    $exitCode = 1
} finally {
    Wait-BeforeExit
}

exit $exitCode
