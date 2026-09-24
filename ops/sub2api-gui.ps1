param([switch]$SmokeTest, [string]$ScreenshotPath, [int]$ScreenshotTab = 0)
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Run this GUI with pwsh.exe -STA -File ops/sub2api-gui.ps1.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $SmokeTest -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $self = $MyInvocation.MyCommand.Path
    Start-Process -FilePath (Get-Command pwsh.exe).Source -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$self`"" -Verb RunAs
    return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'common.ps1')

[Windows.Forms.Application]::EnableVisualStyles()
$form = [Windows.Forms.Form]::new()
$form.Text = 'Sub2API Operations'
$form.Size = [Drawing.Size]::new(880, 640)
$form.MinimumSize = [Drawing.Size]::new(760, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 10)
$form.BackColor = [Drawing.Color]::FromArgb(248, 250, 252)

$tabs = [Windows.Forms.TabControl]::new()
$tabs.Dock = 'Fill'
$tabs.Padding = [Drawing.Point]::new(18, 8)
$form.Controls.Add($tabs)
$operations = [Windows.Forms.TabPage]::new('状态与操作')
$settingsTab = [Windows.Forms.TabPage]::new('连接设置')
$operations.BackColor = $form.BackColor
$settingsTab.BackColor = $form.BackColor
$tabs.TabPages.AddRange(@($operations, $settingsTab))

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$Width = 680) {
    $label = [Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [Drawing.Point]::new($X, $Y)
    $label.Size = [Drawing.Size]::new($Width, 30)
    $label.AutoEllipsis = $true
    return $label
}

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$Width, [scriptblock]$Click) {
    $button = [Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.Location = [Drawing.Point]::new($X, $Y)
    $button.Size = [Drawing.Size]::new($Width, 40)
    $button.FlatStyle = 'System'
    $button.Add_Click($Click)
    return $button
}

$headline = New-Label '服务状态' 28 26
$headline.Font = [Drawing.Font]::new('Microsoft YaHei UI', 16, [Drawing.FontStyle]::Bold)
$operations.Controls.Add($headline)
$devStatus = New-Label '本机开发 18271：检查中' 28 72
$prodStatus = New-Label '本机生产 18272：检查中' 28 106
$linuxStatus = New-Label 'Linux Docker 8080：检查中' 28 140
$syncStatus = New-Label '最近同步：检查中' 28 174
$taskStatus = New-Label '定时任务：检查中' 28 208
$operations.Controls.AddRange(@($devStatus, $prodStatus, $linuxStatus, $syncStatus, $taskStatus))

function Test-Health([string]$HostName, [int]$Port) {
    try {
        $response = Invoke-WebRequest -Uri "http://${HostName}:${Port}/health" -TimeoutSec 2 -UseBasicParsing
        if ($response.StatusCode -eq 200) { return '运行中' }
    } catch { }
    return '未响应'
}

function Refresh-Status {
    $hostName = $script:LinuxHost
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try { $hostName = (Get-OperationsSettings).host } catch { }
    }
    $devStatus.Text = "本机开发 18271：$(Test-Health '127.0.0.1' 18271)"
    $prodStatus.Text = "本机生产 18272：$(Test-Health '127.0.0.1' 18272)"
    $linuxStatus.Text = "Linux Docker ${hostName}:8080：$(Test-Health $hostName 8080)"
    if (Test-Path -LiteralPath $script:SyncStatePath) {
        try {
            $state = Get-Content -LiteralPath $script:SyncStatePath -Raw | ConvertFrom-Json
            $when = ([datetime]$state.completedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
            $syncStatus.Text = "最近同步：$when    用户 $($state.users) / 账号 $($state.accounts) / 渠道 $($state.channels)"
        } catch { $syncStatus.Text = '最近同步：状态文件不可读' }
    } else { $syncStatus.Text = '最近同步：尚无成功记录' }
    $task = Get-ScheduledTask -TaskName 'Sub2API-Linux-Database-Sync' -ErrorAction SilentlyContinue
    $taskStatus.Text = if ($task) { "定时任务：$($task.State)，每天 00:00" } else { '定时任务：未启用' }
}

function Start-Action([string]$Name, [string]$Prompt, [bool]$Elevated = $false) {
    if ($Prompt -and [Windows.Forms.MessageBox]::Show($Prompt, '确认操作', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $pwsh = (Get-Command pwsh.exe).Source
        $actionPath = Join-Path $PSScriptRoot 'action.ps1'
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$actionPath`" -Action $Name"
        if ($Elevated) {
            Start-Process -FilePath $pwsh -ArgumentList $arguments -Verb RunAs | Out-Null
        } else {
            Start-Process -FilePath $pwsh -ArgumentList $arguments | Out-Null
        }
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, '操作失败', 'OK', 'Error') | Out-Null
    }
}

$operations.Controls.Add((New-Button '刷新状态' 28 265 150 { Refresh-Status }))
$operations.Controls.Add((New-Button '启动本机开发' 28 323 180 {
    Start-Action 'StartDev' '若开发服务已运行，当前进程会保持不变。继续吗？'
}))
$operations.Controls.Add((New-Button '启动本机生产' 222 323 180 {
    Start-Action 'StartProd' '将在本机 18272 端口启动第二个实例，连接 Linux 数据库与 Redis；不会关闭开发服务。继续吗？'
}))
$operations.Controls.Add((New-Button '立即同步数据库' 416 323 180 {
    Start-Action 'Sync' '将 Linux 生产库导入本机独立快照库，不覆盖本机开发库。继续吗？'
}))
$operations.Controls.Add((New-Button '启用 00:00 同步' 610 323 180 {
    Start-Action 'Schedule' '注册每天 00:00 的 Windows 定时任务；现在不会执行同步。继续吗？' $true
}))
$operations.Controls.Add((New-Button '获取官方更新' 28 390 180 {
    Start-Action 'Fetch' '只执行 git fetch origin，不自动合并或打包。继续吗？'
}))
$operations.Controls.Add((New-Button '部署并启动 Linux' 222 390 250 {
    Start-Action 'Deploy' '将当前已提交代码推送到个人仓库，并让 Linux 拉取、备份、构建 Docker、启动服务。继续吗？'
}))
$operations.Controls.Add((New-Label '本机 18271 的现有进程不会被这些操作停止。' 28 465 740))

$fieldSpecs = @(
    @('Linux 地址', 'host', '192.168.31.186'),
    @('SSH 用户', 'sshUser', 'fond'),
    @('服务器目录', 'remoteRepo', '/home/fond/xr-gateway'),
    @('PostgreSQL 端口', 'pgPort', '5432'),
    @('数据库名', 'database', 'sub2api'),
    @('数据库用户', 'user', 'sub2api'),
    @('PostgreSQL 密码', 'postgresPassword', ''),
    @('Redis 端口', 'redisPort', '6379'),
    @('Redis 密码', 'redisPassword', '')
)
$fields = @{}
$script:SavedSettings = $null
if (Test-Path -LiteralPath $script:SettingsPath) {
    try { $script:SavedSettings = Get-OperationsSettings } catch { }
}
for ($i = 0; $i -lt $fieldSpecs.Count; $i++) {
    $spec = $fieldSpecs[$i]
    $y = 28 + ($i * 49)
    $label = New-Label $spec[0] 28 ($y + 5) 190
    $settingsTab.Controls.Add($label)
    $box = [Windows.Forms.TextBox]::new()
    $box.Location = [Drawing.Point]::new(230, $y)
    $box.Size = [Drawing.Size]::new(500, 31)
    $box.Anchor = 'Top,Left,Right'
    if ($spec[1] -eq 'remoteRepo') { $box.ReadOnly = $true }
    if ($spec[1] -match 'Password$') {
        $box.UseSystemPasswordChar = $true
    } elseif ($script:SavedSettings -and $script:SavedSettings.PSObject.Properties[$spec[1]]) {
        $box.Text = [string]$script:SavedSettings.($spec[1])
    } else { $box.Text = $spec[2] }
    $settingsTab.Controls.Add($box)
    $fields[$spec[1]] = $box
}

$saveButton = New-Button '保存连接设置' 230 480 180 {
    try {
        $hostValue = $fields.host.Text.Trim()
        if ($hostValue -notmatch '^[a-zA-Z0-9.-]+$') { throw 'Linux 地址格式无效。' }
        $sshUser = $fields.sshUser.Text.Trim()
        if ($sshUser -notmatch '^[a-z_][a-z0-9_-]*$') { throw 'SSH 用户格式无效。' }
        $repo = $fields.remoteRepo.Text.Trim()
        if ($repo -ne '/home/fond/xr-gateway') { throw '当前部署脚本仅支持 /home/fond/xr-gateway。' }
        $pgPort = [int]$fields.pgPort.Text
        $redisPort = [int]$fields.redisPort.Text
        if ($pgPort -lt 1 -or $pgPort -gt 65535 -or $redisPort -lt 1 -or $redisPort -gt 65535) {
            throw '端口必须在 1 到 65535 之间。'
        }
        $pgPassword = if ($fields.postgresPassword.Text) {
            Protect-Value $fields.postgresPassword.Text
        } elseif ($script:SavedSettings) { $script:SavedSettings.postgresPassword } else { $null }
        $redisPassword = if ($fields.redisPassword.Text) {
            Protect-Value $fields.redisPassword.Text
        } elseif ($script:SavedSettings) { $script:SavedSettings.redisPassword } else { $null }
        if (-not $pgPassword -or -not $redisPassword) { throw '请填写 PostgreSQL 和 Redis 密码。' }
        Initialize-SettingsDirectory
        [ordered]@{
            host = $hostValue
            sshUser = $sshUser
            remoteRepo = $repo
            pgPort = $pgPort
            database = $fields.database.Text.Trim()
            user = $fields.user.Text.Trim()
            postgresPassword = $pgPassword
            redisPort = $redisPort
            redisPassword = $redisPassword
        } | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding utf8
        $script:SavedSettings = Get-OperationsSettings
        $fields.postgresPassword.Clear()
        $fields.redisPassword.Clear()
        [Windows.Forms.MessageBox]::Show('连接设置已保存。密码由 Windows DPAPI 加密。', '已保存', 'OK', 'Information') | Out-Null
        Refresh-Status
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, '保存失败', 'OK', 'Error') | Out-Null
    }
}
$settingsTab.Controls.Add($saveButton)

if ($SmokeTest) {
    Write-Host "GUI initialized: tabs=$($tabs.TabPages.Count), settings=$($fields.Count)"
    if ($ScreenshotPath) {
        $tabs.SelectedIndex = $ScreenshotTab
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
        $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
        $bitmap.Save($ScreenshotPath, [Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }
    $form.Dispose()
} else {
    $form.Add_Shown({ Refresh-Status })
    [Windows.Forms.Application]::Run($form)
}
