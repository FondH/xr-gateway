$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Initialize-SettingsDirectory
$temporary = Join-Path $script:SettingsDir 'server-env-import.tmp'
try {
    Invoke-Checked 'scp.exe' @("${script:LinuxTarget}:/home/fond/xr-gateway/deploy/.env", $temporary)
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $temporary) {
        if ($line -match '^([A-Z][A-Z0-9_]*)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
    }
    if (-not $values.POSTGRES_PASSWORD -or -not $values.REDIS_PASSWORD) {
        throw 'Server PostgreSQL or Redis password is missing.'
    }
    $settings = [ordered]@{
        host = $script:LinuxHost
        sshUser = 'fond'
        remoteRepo = '/home/fond/xr-gateway'
        pgPort = 5432
        database = $(if ($values.POSTGRES_DB) { $values.POSTGRES_DB } else { 'sub2api' })
        user = $(if ($values.POSTGRES_USER) { $values.POSTGRES_USER } else { 'sub2api' })
        postgresPassword = Protect-Value $values.POSTGRES_PASSWORD
        redisPort = 6379
        redisPassword = Protect-Value $values.REDIS_PASSWORD
    }
    $settings | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding utf8
    Write-Host 'Linux connection settings saved locally with DPAPI encryption.'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
