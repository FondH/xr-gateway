$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:BackendDir = Join-Path $script:RepoRoot 'backend'
$script:SettingsDir = Join-Path $env:ProgramData 'Sub2API'
$script:SettingsPath = Join-Path $script:SettingsDir 'operations.json'
$script:SyncStatePath = Join-Path $script:SettingsDir 'last-sync.json'
$script:LinuxHost = '192.168.31.186'
$script:LinuxTarget = "fond@$script:LinuxHost"
$script:PgBin = 'G:\Programer\PostgreSQL\18\bin'
$script:SnapshotDatabase = 'sub2api_prod_snapshot'

function Protect-Value([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $cipher = [Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Convert]::ToBase64String($cipher)
}

function Unprotect-Value([string]$Value) {
    $cipher = [Convert]::FromBase64String($Value)
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $cipher, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Get-OperationsSettings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        throw 'Open the GUI Settings tab and save the connection first.'
    }
    return Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
}

function Initialize-SettingsDirectory {
    New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    $acl = Get-Acl -LiteralPath $script:SettingsDir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { $acl.RemoveAccessRuleAll($rule) | Out-Null }
    foreach ($identity in @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators', [Security.Principal.WindowsIdentity]::GetCurrent().Name)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:SettingsDir -AclObject $acl
}

function Get-ConfigField([string]$Section, [string]$Field) {
    $content = Get-Content -LiteralPath (Join-Path $script:BackendDir 'config.yaml') -Raw
    $sectionPattern = '(?m)^' + [regex]::Escape($Section) + ':\r?\n((?:^[ \t]+[^\r\n]*\r?\n)*)'
    $sectionMatch = [regex]::Match($content, $sectionPattern)
    if (-not $sectionMatch.Success) { throw "Missing $Section in backend/config.yaml" }
    $fieldPattern = '(?m)^[ \t]+' + [regex]::Escape($Field) + ':[ \t]*([^\r\n#]+)'
    $match = [regex]::Match($sectionMatch.Groups[1].Value, $fieldPattern)
    if (-not $match.Success) { throw "Missing $Section.$Field in backend/config.yaml" }
    return $match.Groups[1].Value.Trim().Trim('"', "'")
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable exited with $LASTEXITCODE" }
}
