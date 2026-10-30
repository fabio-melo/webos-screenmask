<#
webos-screenmask for Windows.

Uses only what ships with Windows 10 (1809 or later) and Windows 11: PowerShell,
the OpenSSH client (ssh.exe) and tar.exe. Nothing to install.

  screenmask-windows.cmd                         menu
  screenmask-windows.cmd <tv-ip> install         install or upgrade
  screenmask-windows.cmd <tv-ip> uninstall       remove
  screenmask-windows.cmd <tv-ip> <command>...    any screenmask command, e.g. add bottom 20

The TV IP is remembered in %LOCALAPPDATA%\webos-screenmask\tv.txt.
#>
param(
    [string]$Tv,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Command
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ConfigDir = Join-Path $env:LOCALAPPDATA 'webos-screenmask'
$TvFile = Join-Path $ConfigDir 'tv.txt'
$Cli = '/var/lib/screenmask/screenmask'
$Stage = '/tmp/webos-screenmask'
# dropbear on the TV drops any command longer than about 9000 characters.
$ChunkSize = 8000
$SshOptions = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')

function Write-Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Problem([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

function Test-Tools {
    $missing = @()
    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) { $missing += 'ssh.exe' }
    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { $missing += 'tar.exe' }
    if ($missing.Count -eq 0) { return $true }
    Write-Problem "Missing: $($missing -join ', ')"
    Write-Problem 'Install "OpenSSH Client" in Settings > Apps > Optional features.'
    Write-Problem 'tar.exe ships with Windows 10 version 1803 and later.'
    return $false
}

function Get-Tv([string]$Given) {
    if ($Given) { $tv = $Given }
    else {
        $saved = ''
        if (Test-Path $TvFile) { $saved = (Get-Content $TvFile -Raw).Trim() }
        $prompt = 'TV IP address'
        if ($saved) { $prompt = "TV IP address [$saved]" }
        $tv = (Read-Host $prompt).Trim()
        if (-not $tv) { $tv = $saved }
    }
    if ($tv -notmatch '^[A-Za-z0-9.\-:]+$') { throw "Not an IP address or host name: '$tv'" }
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    Set-Content -Path $TvFile -Value $tv -Encoding ASCII
    return $tv
}

# Runs one command on the TV as root and returns its exit code. The command must
# not contain double quotes: Windows PowerShell 5.1 mangles them for native tools.
# Out-Host shows the TV output; without it, the output would become part of the
# function's return value.
function Invoke-Tv([string]$Tv, [string]$Remote) {
    & ssh.exe @SshOptions "root@$Tv" $Remote | Out-Host
    return $LASTEXITCODE
}

function Install-Screenmask([string]$Tv) {
    Write-Step "Packing webos-screenmask"
    $archive = Join-Path $env:TEMP "webos-screenmask-$PID.tgz"
    & tar.exe -czf $archive -C $Root screenmask install.sh uninstall.sh
    if ($LASTEXITCODE -ne 0) { throw 'tar.exe failed to pack the files' }
    $payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive))
    Remove-Item $archive
    $chunks = @()
    for ($i = 0; $i -lt $payload.Length; $i += $ChunkSize) {
        $chunks += $payload.Substring($i, [Math]::Min($ChunkSize, $payload.Length - $i))
    }

    Write-Step "Sending to $Tv ($($chunks.Count) parts; the password is asked once per part)"
    $code = Invoke-Tv $Tv ('rm -rf {0} && mkdir -p {0} && echo {1} > {0}/payload.b64' -f $Stage, $chunks[0])
    if ($code -ne 0) { return $code }
    for ($i = 1; $i -lt $chunks.Count; $i++) {
        $code = Invoke-Tv $Tv ('echo {1} >> {0}/payload.b64' -f $Stage, $chunks[$i])
        if ($code -ne 0) { return $code }
    }

    Write-Step 'Installing on the TV'
    # Unpack, drop Windows line endings if a checkout added them, run the installer.
    $remote = "cd $Stage && tr -d '\r\n' < payload.b64 | base64 -d | tar xzf - && " +
              "find . -type f -exec sed -i 's/\r`$//' {} + && sh install.sh"
    return Invoke-Tv $Tv $remote
}

function Uninstall-Screenmask([string]$Tv) {
    Write-Step "Removing webos-screenmask from $Tv"
    return Invoke-Tv $Tv 'sh /var/lib/screenmask/uninstall.sh'
}

# Passes a screenmask command through. Arguments are checked here, because they
# end up in a shell command line on the TV.
function Invoke-Screenmask([string]$Tv, [string[]]$Arguments) {
    foreach ($argument in $Arguments) {
        if ($argument -notmatch '^[A-Za-z0-9#=._x-]+$') { throw "Unexpected argument: '$argument'" }
    }
    return Invoke-Tv $Tv ("$Cli " + ($Arguments -join ' '))
}

function Install-Key([string]$Tv) {
    Write-Host @'

This creates an SSH key on this PC (if there is none) and adds it to the TV.
After that, the TV stops asking for the password.

Important: once a key is installed, the Homebrew Channel SSH server may turn
off password login. Keep the key in %USERPROFILE%\.ssh. Without it you need
another way into the TV, such as telnet or a Homebrew Channel reset.
'@
    if ((Read-Host 'Continue? (y/N)') -notmatch '^[yY]') { return 0 }
    $key = Join-Path $HOME '.ssh\id_ed25519'
    if (-not (Test-Path $key)) {
        New-Item -ItemType Directory -Force -Path (Join-Path $HOME '.ssh') | Out-Null
        Write-Host 'Creating the key. Press Enter twice to leave the passphrase empty.'
        & ssh-keygen.exe -t ed25519 -f $key | Out-Host
        if ($LASTEXITCODE -ne 0) { return $LASTEXITCODE }
    }
    # Type and body only: the comment may hold characters the TV shell would read.
    $parts = (Get-Content "$key.pub" -Raw).Trim() -split '\s+'
    $line = "$($parts[0]) $($parts[1])"
    $remote = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && " +
              "(grep -qF '$($parts[1])' ~/.ssh/authorized_keys || echo $line >> ~/.ssh/authorized_keys) && " +
              "chmod 600 ~/.ssh/authorized_keys && echo key installed"
    return Invoke-Tv $Tv $remote
}

function Read-Choice([string]$Prompt, [string[]]$Allowed, [string]$Default) {
    while ($true) {
        $text = $Prompt
        if ($Default) { $text = "$Prompt [$Default]" }
        $value = (Read-Host $text).Trim()
        if (-not $value) { $value = $Default }
        if ($Allowed -contains $value) { return $value }
        Write-Problem "Choose one of: $($Allowed -join ', ')"
    }
}

function Read-Number([string]$Prompt, [string]$Default) {
    while ($true) {
        $value = (Read-Host "$Prompt [$Default]").Trim()
        if (-not $value) { $value = $Default }
        if ($value -match '^\d+$') { return $value }
        Write-Problem 'Enter a whole number.'
    }
}

function Show-Menu([string]$Tv) {
    while ($true) {
        Write-Host @"

webos-screenmask  -  TV $Tv

  1  Install or update
  2  Status
  3  Add a mask
  4  Change a mask
  5  Remove a mask
  6  Preview masks in red
  7  Masks on
  8  Masks off
  9  Uninstall
  K  Stop password prompts (SSH key)
  T  Change TV
  Q  Quit
"@
        $choice = (Read-Host 'Choice').Trim().ToUpper()
        try {
            switch ($choice) {
                '1' { $null = Install-Screenmask $Tv }
                '2' { $null = Invoke-Screenmask $Tv @('status') }
                '3' {
                    Write-Host 'Sizes are panel pixels. Start and length run along the edge; length 0 = whole edge.'
                    $edge = Read-Choice 'Edge (top, bottom, left, right)' @('top', 'bottom', 'left', 'right') 'bottom'
                    $size = Read-Number 'Thickness' '20'
                    $start = Read-Number 'Start' '0'
                    $length = Read-Number 'Length' '0'
                    $null = Invoke-Screenmask $Tv @('add', $edge, $size, $start, $length)
                    Write-Host 'Tip: use 6 (preview) to check the position before turning masks on.'
                }
                '4' {
                    $id = (Read-Host 'Mask id (see Status, e.g. m1)').Trim()
                    $key = Read-Choice 'Change (size, start, length, edge, color)' @('size', 'start', 'length', 'edge', 'color') 'size'
                    $value = (Read-Host "New $key (color as #RRGGBB)").Trim()
                    $null = Invoke-Screenmask $Tv @('set', $id, "$key=$value")
                }
                '5' {
                    $id = (Read-Host 'Mask id to remove').Trim()
                    $null = Invoke-Screenmask $Tv @('remove', $id)
                }
                '6' { $null = Invoke-Screenmask $Tv @('preview', (Read-Number 'Seconds' '15')) }
                '7' { $null = Invoke-Screenmask $Tv @('on') }
                '8' { $null = Invoke-Screenmask $Tv @('off') }
                '9' {
                    if ((Read-Host 'Remove webos-screenmask from the TV? (y/N)') -match '^[yY]') {
                        $null = Uninstall-Screenmask $Tv
                    }
                }
                'K' { $null = Install-Key $Tv }
                'T' { $Tv = Get-Tv '' }
                'Q' { return }
                default { Write-Problem 'Unknown choice.' }
            }
        }
        catch {
            Write-Problem $_.Exception.Message
        }
    }
}

if (-not (Test-Tools)) { exit 1 }
if (-not $Tv) {
    Show-Menu (Get-Tv '')
    exit 0
}
$Tv = Get-Tv $Tv
if (-not $Command -or $Command.Count -eq 0) { Show-Menu $Tv; exit 0 }
switch ($Command[0]) {
    'install' { exit (Install-Screenmask $Tv) }
    'uninstall' { exit (Uninstall-Screenmask $Tv) }
    'key' { exit (Install-Key $Tv) }
    default { exit (Invoke-Screenmask $Tv $Command) }
}
