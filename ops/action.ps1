param(
    [Parameter(Mandatory)]
    [ValidateSet('Fetch', 'Deploy', 'Sync', 'StartDev', 'StartProd', 'Schedule')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    switch ($Action) {
        Fetch {
            Invoke-Checked 'git.exe' @('-C', $script:RepoRoot, 'fetch', 'origin')
            Write-Host 'Official changes fetched. Merge and test them yourself before deploying.'
        }
        Deploy {
            $settings = Get-OperationsSettings
            if ($settings.remoteRepo -ne '/home/fond/xr-gateway') {
                throw 'Remote deployment currently supports /home/fond/xr-gateway only.'
            }
            & git.exe -C $script:RepoRoot diff --quiet HEAD --
            if ($LASTEXITCODE -ne 0) { throw 'Commit tracked changes before deployment.' }
            Invoke-Checked 'git.exe' @('-C', $script:RepoRoot, 'push', 'personal', 'HEAD:main')
            Invoke-Checked 'ssh.exe' @('-tt', "$($settings.sshUser)@$($settings.host)", 'cd /home/fond/xr-gateway && git pull --ff-only && bash deploy/ops-deploy.sh')
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
            if (Get-NetTCPConnection -LocalPort 18272 -State Listen -ErrorAction SilentlyContinue) {
                Write-Host 'Local production instance already listens on port 18272. Left it running.'
                break
            }
            $settings = Get-OperationsSettings
            if (-not $settings.redisPassword) { throw 'Configure Redis password in Settings first.' }
            $dataDir = Join-Path $script:SettingsDir 'production-data'
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $environment = @{
                SKIP_SETUP = 'true'
                DATA_DIR = $dataDir
                CONFIG_FILE = (Join-Path $script:BackendDir 'config.yaml')
                SERVER_HOST = '0.0.0.0'
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
            Start-Process -FilePath (Join-Path $script:BackendDir 'sub2api.exe') -WorkingDirectory $script:BackendDir -Environment $environment
            Write-Host 'Started local production instance on port 18272; existing development service was untouched.'
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
