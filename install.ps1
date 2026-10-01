# REFLEX OPS installer for Windows (PowerShell).
#
#   irm https://reflex.riif.com/install.ps1 | iex
#
# Options, set before the line above:
#   $env:REFLEX_VERSION  = 'v0.19.0'   install a specific release
#   $env:REFLEX_BASELINE = '1'         use the build for older processors
#
# It puts reflex.exe in %USERPROFILE%\.reflex\bin and adds that folder to your PATH. Nothing else is changed.
# Written for Windows PowerShell 5.1 and later.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$repo = 'paragonreflex/reflex-ops'
$onWindows = ($env:OS -eq 'Windows_NT')

function Get-Text($uri) {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $uri
    $c = $r.Content
    if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
    return ([string]$c).Trim()
}

# Which release.
$version = $env:REFLEX_VERSION
if (-not $version) {
    try { $version = Get-Text 'https://reflex.riif.com/version.txt' } catch { $version = '' }
}
if (-not $version) { throw 'Could not read the current version from reflex.riif.com. Check the connection and run this again.' }
if (-not $version.StartsWith('v')) { $version = 'v' + $version }

# Which build for this machine.
$arch = 'x64'
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $arch = 'arm64' }
$target = "windows-$arch"
if ($arch -eq 'x64') {
    $baseline = ($env:REFLEX_BASELINE -eq '1')
    if (-not $baseline -and $onWindows) {
        # An older processor without AVX2 needs the baseline build. 40 = AVX2 in the Windows processor feature list.
        try {
            $sig = '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint feature);'
            $cpu = Add-Type -MemberDefinition $sig -Name 'ReflexCpu' -Namespace 'ReflexInstall' -PassThru
            if (-not $cpu::IsProcessorFeaturePresent(40)) { $baseline = $true }
        } catch { }
    }
    if ($baseline) { $target = "$target-baseline" }
}
$asset = "opencode-$target.zip"
$url = "https://github.com/$repo/releases/download/$version/$asset"

# Where it goes.
$dir = $env:REFLEX_INSTALL_DIR
if (-not $dir) {
    $base = $env:USERPROFILE
    if (-not $base) { $base = $HOME }
    $dir = Join-Path (Join-Path $base '.reflex') 'bin'
}
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('reflex_install_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "Installing reflex $version ($target)"
try {
    $zip = Join-Path $tmp $asset
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    } catch {
        throw "Could not download $asset for $version. Check the connection and run this again. ($($_.Exception.Message))"
    }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Join-Path $tmp 'opencode.exe'
    if (-not (Test-Path $exe)) { throw "The download did not contain the program. Run this again, or write to hi@paragonreflex.com." }
    $dest = Join-Path $dir 'reflex.exe'
    try {
        Move-Item -Path $exe -Destination $dest -Force
    } catch {
        throw "Could not replace $dest. If Reflex Ops is open, close it and run this again."
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# PATH: for new terminals (your user setting) and for this one.
if ($onWindows) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    $parts = @($userPath.Split(';') | Where-Object { $_ -ne '' })
    if ($parts -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
        Write-Host "Added $dir to your PATH."
    }
    if (@($env:Path.Split(';')) -notcontains $dir) { $env:Path = $env:Path.TrimEnd(';') + ';' + $dir }
}

Write-Host ''
Write-Host "REFLEX OPS $version installed in $dir"
Write-Host ''
Write-Host 'Next:'
Write-Host '  reflex login     sign in with riif (once)'
Write-Host '  cd <project>     go to your project folder'
Write-Host '  reflex kit       if you work with Claude Code'
Write-Host '  reflex           open Reflex Ops'
Write-Host ''
Write-Host 'If another program (Claude Code, an editor) should find reflex, close and reopen it first.'
