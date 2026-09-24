$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$settings = Get-OperationsSettings
$pgDump = Join-Path $script:PgBin 'pg_dump.exe'
$pgRestore = Join-Path $script:PgBin 'pg_restore.exe'
$psql = Join-Path $script:PgBin 'psql.exe'
foreach ($tool in @($pgDump, $pgRestore, $psql)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Missing PostgreSQL tool: $tool" }
}

function Invoke-Sql([string]$Database, [string]$Sql) {
    & $psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d $Database -At -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Local PostgreSQL query failed ($LASTEXITCODE)" }
}

$backupDir = Join-Path $script:SettingsDir 'snapshots'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir ("linux-{0}.dump" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$next = "${script:SnapshotDatabase}_next"
$previous = "${script:SnapshotDatabase}_previous"

try {
    $env:PGPASSWORD = Unprotect-Value $settings.postgresPassword
    & $pgDump -h $settings.host -p $settings.pgPort -U $settings.user -d $settings.database -Fc -f $backup
    if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $backup).Length -eq 0) {
        throw 'Linux database export failed.'
    }

    $env:PGPASSWORD = Get-ConfigField 'database' 'password'
    Invoke-Sql postgres "DROP DATABASE IF EXISTS $next WITH (FORCE);"
    Invoke-Sql postgres "CREATE DATABASE $next TEMPLATE template0;"
    & $pgRestore --exit-on-error --no-owner --no-privileges -h 127.0.0.1 -U postgres -d $next $backup
    if ($LASTEXITCODE -ne 0) { throw 'Local snapshot restore failed; the previous snapshot was preserved.' }

    $counts = @(Invoke-Sql $next 'SELECT count(*) FROM users; SELECT count(*) FROM accounts; SELECT count(*) FROM channels;')
    if ($counts.Count -ne 3 -or [int]$counts[0] -lt 1) { throw 'Snapshot validation failed.' }
    Invoke-Sql postgres "DROP DATABASE IF EXISTS $previous WITH (FORCE);"
    $exists = @(Invoke-Sql postgres "SELECT 1 FROM pg_database WHERE datname = '$script:SnapshotDatabase';")
    if ($exists.Count -gt 0) {
        Invoke-Sql postgres "ALTER DATABASE $script:SnapshotDatabase RENAME TO $previous;"
    }
    try {
        Invoke-Sql postgres "ALTER DATABASE $next RENAME TO $script:SnapshotDatabase;"
    } catch {
        if ($exists.Count -gt 0) { Invoke-Sql postgres "ALTER DATABASE $previous RENAME TO $script:SnapshotDatabase;" }
        throw
    }

    [ordered]@{
        completedAt = (Get-Date).ToString('o')
        users = [int]$counts[0]
        accounts = [int]$counts[1]
        channels = [int]$counts[2]
        backup = $backup
    } | ConvertTo-Json | Set-Content -LiteralPath $script:SyncStatePath -Encoding utf8
    Get-ChildItem -LiteralPath $backupDir -Filter 'linux-*.dump' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 7 |
        Remove-Item -Force
    Write-Host "Sync complete: users=$($counts[0]), accounts=$($counts[1]), channels=$($counts[2])."
} finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
