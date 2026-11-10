# APEX Lazarus: removes everything setup-local.ps1 created (workspaces, their
# applications, the five accounts and their objects) and the local credentials.
# Runs as SYSDBA through OS authentication.
param(
    [string]$Pdb = 'FREEPDB1',
    [string]$SqlPlus = 'sqlplus'
)
$ErrorActionPreference = 'Stop'

$repo       = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path (Join-Path $repo '.local') 'oracle.json'

# The first line absorbs the byte-order mark Windows PowerShell writes to the pipe.
$sql = @"
prompt
whenever sqlerror exit failure rollback
set echo off feedback on
alter session set container = $Pdb;

begin
    for r_ws in (
        select workspace from apex_workspaces where workspace in ('LZ_PRD', 'LZ_DEV')
    ) loop
        apex_instance_admin.remove_workspace(
            p_workspace         => r_ws.workspace,
            p_drop_users        => 'N',
            p_drop_tablespaces  => 'N');
    end loop;

    for r_user in (
        select username from dba_users
         where username in ('LZ_DEMO_PRD', 'LZ_DEMO_DEV', 'LAZARUS_PRD', 'LAZARUS_DEV', 'LZ_PULL')
    ) loop
        execute immediate 'drop user ' || dbms_assert.enquote_name(r_user.username) || ' cascade';
    end loop;
end;
/
commit;
exit
"@
$sql | & $SqlPlus -L -S '/ as sysdba'
if ($LASTEXITCODE -ne 0) { throw 'Teardown failed.' }
if (Test-Path -LiteralPath $configPath) { Remove-Item -LiteralPath $configPath }
Write-Output 'Lazarus lab removed.'
