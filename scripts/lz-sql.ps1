# APEX Lazarus: runs SQLcl as one of the lab accounts in .local/oracle.json.
# The password goes to SQLcl through standard input, never through arguments
# or logs.
#
#   ./scripts/lz-sql.ps1 -Account LAZARUS_PRD -File db/prod/install.sql
#   ./scripts/lz-sql.ps1 -Account LZ_DEMO_DEV -Command 'apex import -input demo/app'
#
# Relative paths resolve against the repository root, which is also SQLcl's
# working directory.
param(
    [Parameter(Mandatory = $true)][string]$Account,
    [string]$File,
    [string]$Command,
    [string]$SqlCl = 'C:\sqlcl\bin\sql.exe'
)
$ErrorActionPreference = 'Stop'
if (-not $File -and -not $Command) { throw 'Give -File or -Command.' }

$repo   = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $repo '.local/oracle.json') -Raw | ConvertFrom-Json
$secret = $config.accounts.$Account
if (-not $secret) { throw "Unknown account $Account." }

$body = if ($File) { "@`"$File`"" } else { $Command }
# {{secret:ACCOUNT}} in a command is replaced here, so a password another
# script needs (such as the pull account's, for a database link) never
# appears in the caller's command line.
$body = [regex]::Replace($body, '\{\{secret:([A-Z_]+)\}\}', {
    param($match)
    $value = $config.accounts.($match.Groups[1].Value)
    if (-not $value) { throw "Unknown account in placeholder: $($match.Groups[1].Value)" }
    $value
})
# The first line absorbs the byte-order mark Windows PowerShell writes to the
# pipe; SQLcl reports it as an unknown command and continues.
$sql = @"
prompt
cd "$repo"
whenever sqlerror exit failure rollback
connect $Account/"$secret"@$($config.connectString)
$body
exit
"@
# Every known secret is masked in the output, in case an error report echoes
# a statement after substitution.
$secrets = @($config.accounts.PSObject.Properties.Value) + @($config.apexPasswords.PSObject.Properties.Value)
Push-Location $repo
try {
    $sql | & $SqlCl -thin -nohistory -noupdates -S /nolog | ForEach-Object {
        $line = [string]$_
        foreach ($value in $secrets) { $line = $line.Replace($value, '********') }
        $line
    }
    if ($LASTEXITCODE -ne 0) { throw "SQLcl failed for $Account." }
}
finally {
    Pop-Location
}
