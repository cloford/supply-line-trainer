param([Parameter(Mandatory = $true)][string]$ManifestPath)
# Replace only the game executable and PCK; retain staging and backups.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stage = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ManifestPath))
$resultPath = Join-Path $stage 'result.json'
$backupReady = $false
$changed = $false
$newProcess = $null
$install = ''
$payload = @('SupplyLineTrainer.exe', 'SupplyLineTrainer.pck')
function Report([string]$state, [string]$detail) {
    @{ state = $state; detail = $detail; time = [DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
function AssertPlain([string]$path) {
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Reparse point rejected: $path"
        }
    }
}
function RestoreBackup {
    foreach ($name in $payload) {
        $target = Join-Path $install $name
        $previous = Join-Path $install ('.previous-' + $manifest.token + '-' + $name)
        $failed = Join-Path $install ('.failed-' + $manifest.token + '-' + $name)
        if (Test-Path -LiteralPath $failed) { throw 'Failed payload recovery path already exists' }
        AssertPlain $target
        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $failed }
        if (Test-Path -LiteralPath $previous) { Move-Item -LiteralPath $previous -Destination $target }
        else { Copy-Item -LiteralPath (Join-Path (Join-Path $stage 'backup') $name) -Destination $target }
    }
}
function Sha256([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose(); $stream.Dispose() }
}
try {
    AssertPlain $stage
    AssertPlain $ManifestPath
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.token -cnotmatch '^[0-9a-f]{32}\z' -or [IO.Path]::GetFileName($stage) -cne $manifest.token) { throw 'Invalid update token' }
    if ($manifest.sha256 -cnotmatch '^[0-9a-f]{64}\z' -or $manifest.version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z') { throw 'Invalid update metadata' }
    $executable = [IO.Path]::GetFullPath([string]$manifest.executable)
    if ([IO.Path]::GetFileName($executable) -cne $payload[0] -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Invalid installed executable' }
    $install = [IO.Path]::GetDirectoryName($executable)
    if ($stage.StartsWith($install + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $stage -eq $install) { throw 'Stage must be outside installation' }
    AssertPlain $install
    foreach ($name in $payload) {
        AssertPlain (Join-Path $install $name)
        if (-not (Test-Path -LiteralPath (Join-Path $install $name) -PathType Leaf)) { throw "Missing installed payload: $name" }
    }
    # Open the process handle before waiting to avoid PID reuse races.
    $original = [Diagnostics.Process]::GetProcessById([int]$manifest.pid)
    $null = $original.Handle
    if (-not [string]::Equals($original.MainModule.FileName, $executable, [StringComparison]::OrdinalIgnoreCase)) { throw 'Original process does not match executable' }
    $zipPath = Join-Path $stage 'release.zip'
    AssertPlain $zipPath
    $archiveSize = (Get-Item -LiteralPath $zipPath).Length
    if ($archiveSize -ne [long]$manifest.size -or $archiveSize -le 0 -or $archiveSize -gt 268435456) { throw 'Archive size mismatch' }
    if ((Sha256 $zipPath) -cne $manifest.sha256) { throw 'Archive digest mismatch' }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt 128) { throw 'Invalid archive entry count' }
        $root = $null
        $seen = @{}
        $entries = @{}
        $total = 0L
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name.Length -gt 240 -or $name -match '[\\:\x00-\x1f]' -or $name.StartsWith('/')) { throw 'Unsafe ZIP path' }
            foreach ($part in $name.TrimEnd('/').Split('/')) {
                if (-not $part -or $part -eq '.' -or $part -eq '..' -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'Unsafe ZIP component' }
            }
            if (($entry.ExternalAttributes -shr 16 -band 0xF000) -eq 0xA000) { throw 'ZIP symlink rejected' }
            if ($name -ceq $payload[0] -or $name.EndsWith('/' + $payload[0], [StringComparison]::Ordinal)) {
                if ($null -ne $root) { throw 'Duplicate executable' }
                $root = $name.Substring(0, $name.Length - $payload[0].Length)
            }
            $total += $entry.Length
            if ($total -gt 536870912 -or $entry.Length -gt 268435456) { throw 'Expanded archive too large' }
        }
        if ($null -eq $root -or $root.TrimEnd('/').Contains('/')) { throw 'Unexpected ZIP root' }
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name.EndsWith('/')) {
                if ($root -and $name -ceq $root) { continue }
                throw 'Unexpected directory'
            }
            if (-not $name.StartsWith($root, [StringComparison]::Ordinal)) { throw 'Mixed ZIP roots' }
            $relative = $name.Substring($root.Length)
            if ($relative.Contains('/') -or $seen.ContainsKey($relative)) { throw 'Duplicate or nested ZIP entry' }
            $seen[$relative] = $true
            if ($relative -cin $payload) { $entries[$relative] = $entry }
            elseif ($relative -notmatch '(?i)\.(txt|md)$') { throw 'Unexpected ZIP payload' }
        }
        if ($entries.Count -ne 2) { throw 'Missing game payload' }
        $unpack = Join-Path $stage 'unpacked'
        if (Test-Path -LiteralPath $unpack) { throw 'Extraction directory already exists' }
        $null = New-Item -ItemType Directory -Path $unpack
        foreach ($name in $payload) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[$name], (Join-Path $unpack $name)) }
    } finally { $zip.Dispose() }
    [IO.File]::WriteAllText((Join-Path $stage 'helper-ready.txt'), [string]$manifest.token)
    if (-not $original.WaitForExit(120000)) { throw 'Original game is still running; update not applied' }
    $original.Dispose()
    $confirmation = Join-Path $stage 'apply-confirmed.txt'
    if (-not (Test-Path -LiteralPath $confirmation) -or [IO.File]::ReadAllText($confirmation) -cne $manifest.token) { throw 'Game did not confirm update application' }
    $backup = Join-Path $stage 'backup'
    if (Test-Path -LiteralPath $backup) { throw 'Backup already exists' }
    $null = New-Item -ItemType Directory -Path $backup
    foreach ($name in $payload) { Copy-Item -LiteralPath (Join-Path $install $name) -Destination (Join-Path $backup $name) }
    $backupReady = $true
    foreach ($name in $payload) {
        AssertPlain (Join-Path $install $name)
        $previous = Join-Path $install ('.previous-' + $manifest.token + '-' + $name)
        if (Test-Path -LiteralPath $previous) { throw 'Previous payload recovery path already exists' }
        Move-Item -LiteralPath (Join-Path $install $name) -Destination $previous
        $changed = $true
        Copy-Item -LiteralPath (Join-Path $unpack $name) -Destination (Join-Path $install $name)
    }
    $ack = Join-Path $stage 'started.json'
    if (Test-Path -LiteralPath $ack) { throw 'Startup acknowledgement already exists' }
    $arguments = @('--', '--supply-line-update-token', $manifest.token, '--supply-line-update-ack', ('"' + $ack + '"'))
    $newProcess = Start-Process -FilePath $executable -WorkingDirectory $install -ArgumentList $arguments -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if (Test-Path -LiteralPath $ack) {
            try {
                $response = Get-Content -LiteralPath $ack -Raw | ConvertFrom-Json
                if ($response.token -ceq $manifest.token -and $response.version -ceq $manifest.version -and -not $newProcess.HasExited) {
                    Report 'applied' 'Startup acknowledged; previous executable and data retained in backup'
                    exit 0
                }
            } catch { }
        }
        if ($newProcess.HasExited) { throw 'Updated game exited before startup acknowledgement' }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Updated game did not acknowledge startup'
} catch {
    $detail = $_.Exception.Message
    if ($changed -and $backupReady) {
        if ($null -ne $newProcess -and -not $newProcess.HasExited) {
            Report 'manual-recovery' ($detail + '; game is still running. Close it, then copy the retained backup files into the installation.')
        } else {
            try {
                RestoreBackup
                Report 'rolled-back' $detail
                $null = Start-Process -FilePath (Join-Path $install $payload[0]) -WorkingDirectory $install
            } catch { Report 'manual-recovery' ($detail + '; rollback error: ' + $_.Exception.Message) }
        }
    } else { Report 'rejected' $detail }
    exit 1
}
