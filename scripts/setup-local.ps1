# APEX Lazarus: local lab on one Oracle Database Free PDB with APEX 26.2.
#
# Creates the two environments as two workspaces on the same APEX instance:
#   LZ_PRD  plays production   (parsing schema LZ_DEMO_PRD, Lazarus schema LAZARUS_PRD)
#   LZ_DEV  plays development  (parsing schema LZ_DEMO_DEV, Lazarus schema LAZARUS_DEV)
# plus LZ_PULL, the only account that crosses zones (SELECT on LZ_INBOX).
#
# Runs as SYSDBA through OS authentication. Generated passwords are written
# only to the ignored .local/oracle.json and are never printed.
param(
    [string]$Pdb = 'FREEPDB1',
    [string]$SqlPlus = 'C:\app\geefa\product\26ai\dbhomeFree\bin\sqlplus.exe'
)
$ErrorActionPreference = 'Stop'

$repo       = Split-Path -Parent $PSScriptRoot
$localPath  = Join-Path $repo '.local'
$configPath = Join-Path $localPath 'oracle.json'
if (Test-Path -LiteralPath $configPath) {
    throw 'Local configuration already exists. Refusing to replace credentials.'
}
New-Item -ItemType Directory -Path $localPath -Force | Out-Null

function New-Secret { 'Lz' + [guid]::NewGuid().ToString('N') + '9!' }

$accounts = [ordered]@{
    LZ_DEMO_PRD = New-Secret
    LZ_DEMO_DEV = New-Secret
    LAZARUS_PRD = New-Secret
    LAZARUS_DEV = New-Secret
    LZ_PULL     = New-Secret
}
$apexPasswords = [ordered]@{
    LZ_PRD = New-Secret
    LZ_DEV = New-Secret
}
[ordered]@{
    connectString = "localhost:1521/$Pdb"
    baseUrl       = 'http://localhost:8080/ords'
    accounts      = $accounts
    apexUser      = 'LZ_ADMIN'
    apexPasswords = $apexPasswords
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding utf8

# The first line absorbs the byte-order mark Windows PowerShell writes to the pipe.
$sql = @"
prompt
whenever sqlerror exit failure rollback
set echo off feedback on
alter session set container = $Pdb;

-- Demo application parsing schemas
create user LZ_DEMO_PRD identified by "$($accounts.LZ_DEMO_PRD)" default tablespace USERS quota 200M on USERS;
create user LZ_DEMO_DEV identified by "$($accounts.LZ_DEMO_DEV)" default tablespace USERS quota 200M on USERS;
grant create session, create table, create view, create sequence, create procedure,
      create trigger, create synonym to LZ_DEMO_PRD;
grant create session, create table, create view, create sequence, create procedure,
      create trigger, create synonym to LZ_DEMO_DEV;

-- Lazarus schemas
create user LAZARUS_PRD identified by "$($accounts.LAZARUS_PRD)" default tablespace USERS quota 200M on USERS;
grant create session, create table, create sequence, create procedure, create trigger, create job to LAZARUS_PRD;
grant execute on sys.dbms_crypto to LAZARUS_PRD;

create user LAZARUS_DEV identified by "$($accounts.LAZARUS_DEV)" default tablespace USERS quota 200M on USERS;
grant create session, create table, create view, create sequence, create procedure,
      create trigger, create job, create synonym, create database link to LAZARUS_DEV;

-- The pull account: it gets SELECT on LZ_INBOX from LAZARUS_PRD, nothing else
create user LZ_PULL identified by "$($accounts.LZ_PULL)";
grant create session to LZ_PULL;

begin
    apex_instance_admin.add_workspace(p_workspace => 'LZ_PRD', p_primary_schema => 'LZ_DEMO_PRD');
    apex_instance_admin.add_workspace(p_workspace => 'LZ_DEV', p_primary_schema => 'LZ_DEMO_DEV');

    apex_util.set_security_group_id(apex_util.find_security_group_id('LZ_PRD'));
    apex_util.create_user(
        p_user_name                    => 'LZ_ADMIN',
        p_email_address                => 'lz-admin@example.invalid',
        p_web_password                 => '$($apexPasswords.LZ_PRD)',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_change_password_on_first_use => 'N');

    apex_util.set_security_group_id(apex_util.find_security_group_id('LZ_DEV'));
    apex_util.create_user(
        p_user_name                    => 'LZ_ADMIN',
        p_email_address                => 'lz-admin@example.invalid',
        p_web_password                 => '$($apexPasswords.LZ_DEV)',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_change_password_on_first_use => 'N');
end;
/
commit;
exit
"@
$sql | & $SqlPlus -L -S '/ as sysdba'
if ($LASTEXITCODE -ne 0) { throw 'Local setup failed. The configuration file is kept for diagnosis.' }
Write-Output 'Lazarus lab created (workspaces LZ_PRD and LZ_DEV); credentials kept only in .local/oracle.json.'
