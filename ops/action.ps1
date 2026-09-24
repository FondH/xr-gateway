param(
    [Parameter(Mandatory)]
    [ValidateSet('Fetch', 'Deploy', 'Sync', 'StartDev', 'StartProd', 'StartAll', 'Schedule')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Invoke-LinuxDeploy {
    $settings = Get-OperationsSettings
    if ($settings.remoteRepo -ne '/home/fond/xr-gateway') {
        throw 'Remote deployment currently supports /home/fond/xr-gateway only.'
    }
    & git.exe -C $script:RepoRoot diff --quiet HEAD --
    if ($LASTEXITCODE -ne 0) { throw 'Commit tracked changes before deployment.' }
    Invoke-Checked 'git.exe' @('-C', $script:RepoRoot, 'push', 'personal', 'HEAD:main')
    Invoke-Checked 'ssh.exe' @('-tt', "$($settings.sshUser)@$($settings.host)", 'cd /home/fond/xr-gateway && git pull --ff-only && bash deploy/ops-deploy.sh')
}

function Start-LocalProduction {
    $existing = @(Get-NetTCPConnection -LocalPort 18272 -State Listen -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        if (@($existing | Where-Object LocalAddress -NotIn @('127.0.0.1', '::1')).Count -gt 0) {
            throw 'An existing service on port 18272 is not limited to localhost.'
        }
        Write-Host 'Local production instance already listens on port 18272. Left it running.'
        return
    }
    $settings = Get-OperationsSettings
    if (-not $settings.redisPassword) { throw 'Configure Redis password in Settings first.' }
    $dataDir = Join-Path $script:SettingsDir 'production-data'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    $environment = @{
        SKIP_SETUP = 'true'
        DATA_DIR = $dataDir
        CONFIG_FILE = (Join-Path $script:BackendDir 'config.yaml')
        SERVER_HOST = '127.0.0.1'
        SERVER_PORT = '18272'
        DATABASE_HOST = $settings.host
        DATABASE_PORT = [string]$settings.pgPort
        DATABASE_USER = $settings.user
        DATABASE_PASSWORD = Unprotect-Value $settings.postgresPassword
        DATABASE_DBNAME = $settings.database
        REDIS_HOST = $settings.host
        REDIS_PORT = [string]$settings.redisPort
        REDIS_PASSWORD = Unprotect-Value $settings.redisPassword
    }
    $process = Start-Process -FilePath (Join-Path $script:BackendDir 'sub2api.exe') -WorkingDirectory $script:BackendDir -Environment $environment -PassThru
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        if ($process.HasExited) { throw "Local production exited during startup with code $($process.ExitCode)." }
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18272/health' -TimeoutSec 2 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $bindings = @(Get-NetTCPConnection -LocalPort 18272 -State Listen -ErrorAction SilentlyContinue)
                if (@($bindings | Where-Object LocalAddress -NotIn @('127.0.0.1', '::1')).Count -gt 0) {
                    throw 'Local production is listening beyond localhost; inspect its configuration.'
                }
                Write-Host 'Local production is healthy on 127.0.0.1:18272; development service was untouched.'
                return
            }
        } catch {
            if ($_.Exception.Message -like '*beyond localhost*') { throw }
        }
        Start-Sleep -Seconds 5
    }
    throw 'Local production did not become healthy within 60 seconds.'
}

try {
    switch ($Action) {
        Fetch {
            Invoke-Checked 'git.exe' @('-C', $script:RepoRoot, 'fetch', 'origin')
            Write-Host 'Official changes fetched. Merge and test them yourself before deploying.'
        }
        Deploy {
            Invoke-LinuxDeploy
        }
        Sync {
            & (Join-Path $PSScriptRoot 'sync-prod-db.ps1')
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Sync failed: $LASTEXITCODE" }
        }
        StartDev {
            if (Get-NetTCPConnection -LocalPort 18271 -State Listen -ErrorAction SilentlyContinue) {
                Write-Host 'Local development service already listens on port 18271. Left it running.'
                break
            }
            $environment = @{
                SKIP_SETUP = 'true'
                DATA_DIR = $script:BackendDir
                CONFIG_FILE = (Join-Path $script:BackendDir 'config.yaml')
            }
            Start-Process -FilePath (Join-Path $script:BackendDir 'sub2api.exe') -WorkingDirectory $script:BackendDir -Environment $environment
            Write-Host 'Started local development instance on port 18271.'
        }
        StartProd {
            Start-LocalProduction
        }
        StartAll {
            Invoke-LinuxDeploy
            $settings = Get-OperationsSettings
            $healthy = $false
            for ($attempt = 0; $attempt -lt 24; $attempt++) {
                try {
                    $response = Invoke-WebRequest -Uri "http://$($settings.host):8080/health" -TimeoutSec 3 -UseBasicParsing
                    if ($response.StatusCode -eq 200) { $healthy = $true; break }
                } catch { }
                Start-Sleep -Seconds 5
            }
            if (-not $healthy) { throw 'Linux application did not become healthy; local production was not started.' }
            Start-LocalProduction
        }
        Schedule {
            Get-OperationsSettings | Out-Null
            $taskName = 'Sub2API-Linux-Database-Sync'
            $pwsh = (Get-Command pwsh.exe).Source
            $syncScript = Join-Path $PSScriptRoot 'sync-prod-db.ps1'
            $taskAction = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -File `"$syncScript`""
            $trigger = New-ScheduledTaskTrigger -Daily -At '00:00'
            $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
            Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $taskSettings -Force | Out-Null
            Write-Host "Scheduled $taskName daily at 00:00. No sync was started now."
        }
    }
} catch {
    Write-Error $_
    exit 1
}
