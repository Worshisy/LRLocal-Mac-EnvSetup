# host-001-ssh-config-windows.ps1 - Windows companion to host-000-ssh-config.sh.
# RUN THIS ON A WINDOWS OPERATOR PC (laptop / lab box), not on a mini.
#
#   powershell -ExecutionPolicy Bypass -File .\host-001-ssh-config-windows.ps1
#
# host-000 is the single source of truth for the ddh-mac-0X / ddh-pi4-beacon
# blocks; this script runs it through Git Bash and then fixes the three things
# that only bite on Windows:
#
#   1. ACLs. host-000 rewrites ~/.ssh/config via mktemp+mv, so the new file
#      inherits group access and Windows OpenSSH refuses it outright:
#      "Bad owner or permissions on C:\Users\<you>/.ssh/config". chmod 600 in
#      the bash script does nothing about ACLs.
#   2. An `ssh -F <file>` wrapper. A PowerShell profile that defines
#      `function ssh { & ssh.exe -F "C:\ssh\ssh_config.txt" @args }` makes
#      ssh read THAT file instead of ~/.ssh/config, so the field shortcuts are
#      invisible ("Could not resolve hostname ddh-mac-03"). We detect it and
#      Include the per-user config from it.
#   3. A world-writable -F config. Those live outside ~/.ssh (e.g. C:\ssh) and
#      inherit C:\'s ACL, giving every local account Modify on a file that can
#      run commands via ProxyCommand. OpenSSH does not permission-check -F
#      files, so nothing warns you.
#
# Idempotent: re-run it after every `git pull` that touches host-000.
[CmdletBinding()]
param(
    # Skip running host-000 (fix permissions / Include only).
    [switch] $SkipHost000
)

$ErrorActionPreference = 'Stop'
function Say  ($m) { Write-Host "`n[host-win] $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  [ok] $m"      -ForegroundColor Green }
function Warn ($m) { Write-Host "  [!] $m"       -ForegroundColor Yellow }

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$userCfg = Join-Path $env:USERPROFILE '.ssh\config'

# [c] Windows PowerShell 5.1 wraps a native exe's stderr in ErrorRecords, which
# $ErrorActionPreference='Stop' then treats as terminating - icacls printing
# "Access is denied." would kill the script instead of letting us report it.
# Run native tools through here and judge them by their exit code only.
function Invoke-Native {
    param([string] $Exe, [string[]] $Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try   { $out = & $Exe @Arguments 2>$null; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out } }
    finally { $ErrorActionPreference = $prev }
}

# [c] The CONSOLE user, not $env:USERNAME. Elevating with "Run as administrator"
# can hand you a different admin account, and granting that one instead locks the
# real operator out of their own ssh config.
function Get-OperatorAccount {
    try { $u = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { $u = $null }
    if (-not $u) { $u = "$env:USERDOMAIN\$env:USERNAME" }
    return $u
}

# [c] Can the operator still READ this file? Every ACL change here is followed by
# this check - see Set-OwnerOnlyAcl for why a "successful" icacls can still lock
# the file. Reads as the current process; good enough, the caller is the operator.
function Test-Readable ($path) {
    try { $null = Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction Stop; return $true }
    catch { return $false }
}

# [c] Tighten a FILE. Never pass (OI)(CI) here: those are container-inheritance
# flags, and icacls applied to a file reports success while leaving an EMPTY DACL
# - the file becomes unreadable even by its owner, and ssh dies with
# "Can't open user config file ...: Permission denied". Learned the hard way,
# 2026-08-05, on C:\ssh\ssh_config.txt. Verifies, and reverts to inheritance if
# the result is unreadable.
function Set-OwnerOnlyAcl ($path, $account) {
    $r = Invoke-Native icacls @($path, '/inheritance:r', '/grant:r', "${account}:F", 'SYSTEM:F', 'Administrators:F')
    if ($r.Code -ne 0) { return $false }
    if (Test-Readable $path) { return $true }
    $null = Invoke-Native icacls @($path, '/reset')     # fall back to inherited rights
    Warn "tightening $path made it unreadable - reverted to inherited permissions"
    return (Test-Readable $path)
}

# ── 1. Run host-000 through Git Bash ─────────────────────────────────────────
if (-not $SkipHost000) {
    $bash = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $bash) { $bash = (Get-Command bash.exe -ErrorAction SilentlyContinue).Source }

    if ($bash) {
        Say "Running host-000-ssh-config.sh via $bash"
        & $bash -lc "cd '$($here -replace '\\','/')' && ./host-000-ssh-config.sh"
        if ($LASTEXITCODE -ne 0) { throw "host-000-ssh-config.sh failed ($LASTEXITCODE)" }
    } else {
        Warn "Git Bash not found - install Git for Windows, or run host-000-ssh-config.sh"
        Warn "on any shell that has bash, then re-run this with -SkipHost000."
    }
}
if (-not (Test-Path $userCfg)) { throw "no $userCfg - run host-000-ssh-config.sh first" }

# ── 2. Lock down ~/.ssh/config so Windows OpenSSH will read it ────────────────
# [c] owner + SYSTEM + Administrators only; any other grant (inherited Users /
# Authenticated Users) makes ssh.exe abort before it parses a single line.
$acct = Get-OperatorAccount
Say "Fixing ACLs on $userCfg (granting $acct)"
if (Set-OwnerOnlyAcl $userCfg $acct) { Ok "owner-only (this is what host-000's mktemp+mv resets every run)" }
else { Warn "could not make $userCfg owner-only AND readable - ssh.exe will refuse it"; exit 1 }

# ── 3. Follow an `ssh -F <file>` wrapper, if the profile defines one ──────────
# [c] Two OpenSSH gotchas make the naive Include fail silently, both learned the
# hard way: it must sit ABOVE the first Host block (otherwise it is scoped to
# the preceding host), and the path needs forward slashes, because Include is
# glob()ed and glob treats \ as an escape - a backslash path matches nothing.
$mark = '# >>> LRLocal per-user config (managed by host-001-ssh-config-windows.ps1) >>>'
$wrapperCfg = $null
if ($PROFILE -and (Test-Path $PROFILE)) {
    $m = Select-String -Path $PROFILE -Pattern 'ssh\.exe\s+-F\s+"?([^"\s]+)"?' | Select-Object -First 1
    if ($m) { $wrapperCfg = $m.Matches[0].Groups[1].Value }
}

if (-not $wrapperCfg) {
    Ok "no 'ssh -F' wrapper in your PowerShell profile - ~/.ssh/config is used directly"
} elseif (-not (Test-Path $wrapperCfg)) {
    Warn "profile points ssh at $wrapperCfg, which does not exist - fix or remove that wrapper"
} else {
    Say "Profile wraps ssh with -F $wrapperCfg - making it Include the per-user config"
    $raw = Get-Content $wrapperCfg -Raw
    # [c] match on the included PATH, not just our marker: an Include added by
    # hand before this script existed would otherwise be duplicated every run.
    # Compare slash-normalised + lowercased, since either form works in the file.
    $want = ($userCfg -replace '\\', '/').ToLower()
    $already = @(Get-Content $wrapperCfg | Where-Object {
        $_ -match '^\s*Include\s' -and (($_ -replace '\\', '/').ToLower().Contains($want))
    }).Count -gt 0
    if (($raw -like "*$mark*") -or $already) {
        Ok "Include already present"
    } else {
        $incPath = $userCfg -replace '\\', '/'
        $header  = @(
            $mark,
            '# Field shortcuts (ddh-mac-0X / ddh-pi4-beacon) are written to the per-user',
            '# config by host-000-ssh-config.sh. Must stay ABOVE the first Host block, and',
            '# needs forward slashes: Include is glob()ed and glob eats backslashes.',
            "Include `"$incPath`"",
            '# <<< LRLocal per-user config <<<',
            ''
        ) -join "`r`n"
        Copy-Item $wrapperCfg "$wrapperCfg.bak" -Force
        Set-Content -Path $wrapperCfg -Value ($header + $raw) -Encoding ascii -NoNewline
        Ok "Include added at the top (backup: $wrapperCfg.bak)"
    }
    # [c] -F files skip OpenSSH's permission check, so a config in e.g. C:\ssh
    # keeps C:\'s inherited "Authenticated Users: Modify" - a ProxyCommand line
    # away from code execution as you. Lock the whole directory.
    $dir = Split-Path -Parent $wrapperCfg
    if ($dir -and $dir -notmatch '^[A-Za-z]:\\?$') {
        $loose = @((Invoke-Native icacls @($dir)).Out |
                   Where-Object { $_ -match 'Authenticated Users|BUILTIN\\Users|Everyone' }).Count -gt 0
        if (-not $loose) {
            Ok "$dir already owner-only"
        } else {
            # [c] (OI)(CI) on the DIRECTORY only, and NO /T - see Set-OwnerOnlyAcl:
            # container flags pushed onto child files leave them with an empty DACL.
            # Children are then made to inherit the parent's clean ACL via /reset.
            $r = Invoke-Native icacls @($dir, '/inheritance:r', '/grant:r',
                    "${acct}:(OI)(CI)F", 'SYSTEM:(OI)(CI)F', 'Administrators:(OI)(CI)F')
            if ($r.Code -eq 0) { $null = Invoke-Native icacls @("$dir\*", '/reset', '/T') }
            if ($r.Code -eq 0 -and (Test-Readable $wrapperCfg)) {
                Ok "locked down $dir (was writable by every local account)"
            } elseif ($r.Code -eq 0) {
                $null = Invoke-Native icacls @($dir, '/inheritance:e')
                $null = Invoke-Native icacls @("$dir\*", '/reset', '/T')
                Warn "locking $dir made $wrapperCfg unreadable - reverted. Fix by hand:"
                Warn "  takeown /f $dir /r /d y   (elevated), then re-run this script"
            } else {
                # [c] icacls needs ownership; a dir created by an installer or under
                # C:\ often is not owned by you. Do NOT claim success here - an
                # -F config anyone can edit is a ProxyCommand away from code exec.
                Warn "could not tighten $dir (icacls exit $($r.Code)) - every local"
                Warn "account can still modify $wrapperCfg. Re-run this script as"
                Warn "Administrator, or move that config under $env:USERPROFILE\.ssh\."
            }
        }
    }
}

# ── 4. Verify ────────────────────────────────────────────────────────────────
Say "Verifying"
$fail = 0
foreach ($h in @('ddh-mac-01', 'ddh-mac-03', 'ddh-pi4-beacon')) {
    # [c] plain ssh.exe, NOT the profile's ssh function - this must prove what a
    # bare `ssh <host>` resolves to, wrapper and all, exactly as the operator types it
    $g  = (Invoke-Native 'ssh.exe' @('-G', $h)).Out
    $hn = ($g | Select-String '^hostname ' | Select-Object -First 1) -replace '^hostname ', ''
    $un = ($g | Select-String '^user '     | Select-Object -First 1) -replace '^user ', ''
    if (-not $hn -or $hn -eq $h) { Warn "$h -> unresolved (config not applied)"; $fail++ }
    else                         { Ok   "$h -> $un@$hn" }
}
if ($fail) {
    Warn "Some hosts did not resolve. Check that (Get-Command ssh).Source is the"
    Warn "binary you expect and that no other -F wrapper shadows it."
    exit 1
}
Say "Done - try:  ssh ddh-mac-01   (after joining that unit's Wi-Fi)"
