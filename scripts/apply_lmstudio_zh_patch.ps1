param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [string]$OutputPath,

    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ProfilesRoot = Join-Path $ProjectRoot 'versions'

function Read-VersionProfiles {
    $profiles = @(
        Get-ChildItem -LiteralPath $ProfilesRoot -Filter 'profile.json' -File -Recurse |
            Sort-Object FullName |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    )
    if ($profiles.Count -eq 0) {
        throw "No version profiles were found: $ProfilesRoot"
    }
    return $profiles
}

function Resolve-MainWindowPath {
    param(
        [string]$InputPath,
        [object[]]$Profiles
    )

    $resolved = [System.IO.Path]::GetFullPath($InputPath)
    if ([System.IO.File]::Exists($resolved)) {
        $matches = @($Profiles | Where-Object {
            $candidate = [System.IO.Path]::Combine(
                [System.IO.Path]::GetDirectoryName($resolved),
                $_.mainWindowRelativePath.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
            )
            $candidate -eq $resolved
        })
        if ($matches.Count -eq 0) {
            return [pscustomobject]@{ Path = $resolved; AppRoot = $null }
        }
        return [pscustomobject]@{ Path = $resolved; AppRoot = $null }
    }

    foreach ($profile in $Profiles) {
        $relative = $profile.mainWindowRelativePath.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
        $candidate = [System.IO.Path]::Combine($resolved, $relative)
        if ([System.IO.File]::Exists($candidate)) {
            return [pscustomobject]@{ Path = $candidate; AppRoot = $resolved }
        }
    }

    throw "main_window.js was not found: $resolved"
}

function Get-ProfileForHash {
    param(
        [object[]]$Profiles,
        [string]$Hash
    )

    foreach ($profile in $Profiles) {
        if ($profile.originalSha256 -and $profile.originalSha256.ToUpperInvariant() -eq $Hash) {
            return [pscustomobject]@{ Profile = $profile; State = 'original' }
        }
        if ($profile.patchedSha256 -and $profile.patchedSha256 -ne 'TO_BE_COMPUTED' -and $profile.patchedSha256.ToUpperInvariant() -eq $Hash) {
            return [pscustomobject]@{ Profile = $profile; State = 'patched' }
        }
        if ($profile.legacyCurrentSha256 -and $profile.legacyCurrentSha256.ToUpperInvariant() -eq $Hash) {
            return [pscustomobject]@{ Profile = $profile; State = 'legacy' }
        }
    }
    return $null
}

function Find-ObjectEnd {
    param(
        [string]$Text,
        [int]$StartIndex
    )

    if ($StartIndex -lt 0 -or $StartIndex -ge $Text.Length -or $Text[$StartIndex] -ne '{') {
        throw "Invalid object start index: $StartIndex"
    }

    $depth = 0
    $quote = [char]0
    $escaped = $false
    for ($index = $StartIndex; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($quote -ne [char]0) {
            if ($escaped) {
                $escaped = $false
                continue
            }
            if ($character -eq '\') {
                $escaped = $true
                continue
            }
            if ($character -eq $quote) {
                $quote = [char]0
            }
            continue
        }
        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            continue
        }
        if ($character -eq '{') {
            $depth++
            continue
        }
        if ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $index
            }
        }
    }
    throw "Could not find the object end after index $StartIndex"
}

function Get-JsonObjectCompact {
    param([string]$Path)
    $object = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $object | ConvertTo-Json -Compress -Depth 100
}

$profiles = Read-VersionProfiles
$targetInfo = Resolve-MainWindowPath -InputPath $TargetPath -Profiles $profiles
$mainWindowPath = $targetInfo.Path

if (-not $OutputPath) {
    $running = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^LM Studio$|^LMStudio$' }
    if ($running) {
        throw 'LM Studio is running. Close it completely before applying or restoring the patch.'
    }
}

$currentHash = (Get-FileHash -LiteralPath $mainWindowPath -Algorithm SHA256).Hash.ToUpperInvariant()
$match = Get-ProfileForHash -Profiles $profiles -Hash $currentHash

if ($Restore) {
    if (-not $match -or $match.State -ne 'patched') {
        throw "Restore refused. The target is not a recognized patched file. Current main_window.js SHA256=$currentHash"
    }
    $profile = $match.Profile
    $backupPath = "$mainWindowPath$($profile.backupSuffix)"
    if (-not [System.IO.File]::Exists($backupPath)) {
        throw "Backup file was not found: $backupPath"
    }
    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($backupHash -ne $profile.originalSha256.ToUpperInvariant()) {
        throw "Backup verification failed for LM Studio $($profile.version). Refusing to restore SHA256=$backupHash"
    }
    $restoreTempPath = "$mainWindowPath.$($profile.profileId)-restore-$PID.tmp"
    $restoreSwapPath = "$mainWindowPath.$($profile.profileId)-restore-swap-$PID.tmp"
    Copy-Item -LiteralPath $backupPath -Destination $restoreTempPath
    try {
        [System.IO.File]::Replace($restoreTempPath, $mainWindowPath, $restoreSwapPath)
        $restoredHash = (Get-FileHash -LiteralPath $mainWindowPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($restoredHash -ne $profile.originalSha256.ToUpperInvariant()) {
            throw "Restore verification failed. SHA256=$restoredHash"
        }
    } finally {
        if ([System.IO.File]::Exists($restoreTempPath)) { Remove-Item -LiteralPath $restoreTempPath -Force }
        if ([System.IO.File]::Exists($restoreSwapPath)) { Remove-Item -LiteralPath $restoreSwapPath -Force }
    }
    Write-Output "Original file restored for LM Studio $($profile.version): $mainWindowPath"
    Write-Output "SHA256=$restoredHash"
    exit 0
}

if (-not $match) {
    throw "Version check failed. Refusing to modify an unknown main_window.js. Current SHA256=$currentHash"
}

$profile = $match.Profile
if ($match.State -eq 'patched') {
    Write-Output "LM Studio $($profile.version) deep Chinese patch is already installed. No files were changed."
    Write-Output "SHA256=$currentHash"
    exit 0
}
if ($match.State -eq 'legacy') {
    if (-not $profile.legacyBackupSuffix -or -not $profile.legacyOriginalSha256) {
        throw "A legacy patch was detected for LM Studio $($profile.version), but no safe upgrade profile is defined."
    }
    $legacyBackupPath = "$mainWindowPath$($profile.legacyBackupSuffix)"
    if (-not [System.IO.File]::Exists($legacyBackupPath)) {
        throw "The legacy patch is installed, but its original backup is missing: $legacyBackupPath"
    }
    $legacyBackupHash = (Get-FileHash -LiteralPath $legacyBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($legacyBackupHash -ne $profile.legacyOriginalSha256.ToUpperInvariant()) {
        throw "The legacy backup failed verification. Refusing to upgrade. SHA256=$legacyBackupHash"
    }
    $sourceMainWindowPath = $legacyBackupPath
    $upgradingFromLegacy = $true
} elseif ($match.State -eq 'original') {
    $sourceMainWindowPath = $mainWindowPath
    $upgradingFromLegacy = $false
} else {
    throw "Unsupported target state: $($match.State)"
}

if (-not $profile.patchedSha256 -or $profile.patchedSha256 -eq 'TO_BE_COMPUTED') {
    throw "Version profile $($profile.version) has no published patched SHA256 yet."
}

$baselineRoot = Join-Path $ProjectRoot $profile.baselineRoot
$payloadRoot = Join-Path $ProjectRoot $profile.payloadRoot
$overlayPath = Join-Path $ProjectRoot $profile.overlayPath
if (-not [System.IO.Directory]::Exists($baselineRoot)) { throw "Baseline directory is missing: $baselineRoot" }
if (-not [System.IO.Directory]::Exists($payloadRoot)) { throw "Payload directory is missing: $payloadRoot" }
if (-not [System.IO.File]::Exists($overlayPath)) { throw "Deep translation overlay is missing: $overlayPath" }

$text = [System.IO.File]::ReadAllText($sourceMainWindowPath, [System.Text.Encoding]::UTF8)
$payloadFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Filter '*.json' -File | Sort-Object Name)
if ($payloadFiles.Count -eq 0) { throw "No locale payload files were found: $payloadRoot" }
$patchedNamespaces = New-Object System.Collections.Generic.List[string]

foreach ($payloadFile in $payloadFiles) {
    $officialPath = Join-Path $baselineRoot $payloadFile.Name
    if (-not [System.IO.File]::Exists($officialPath)) {
        throw "Official Chinese baseline is missing: $officialPath"
    }
    $officialCompact = Get-JsonObjectCompact -Path $officialPath
    $payloadCompact = Get-JsonObjectCompact -Path $payloadFile.FullName
    $payloadEmbedded = $payloadCompact.Replace('\', '\\').Replace("'", "\'")
    $payloadEmbedded = $payloadEmbedded.Replace(([char]0x2028).ToString(), '\\u2028')
    $payloadEmbedded = $payloadEmbedded.Replace(([char]0x2029).ToString(), '\\u2029')
    $prefixLength = [Math]::Min(120, $officialCompact.Length)
    $prefix = $officialCompact.Substring(0, $prefixLength)
    $startIndex = $text.IndexOf($prefix, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) {
        throw "Could not locate the Chinese locale object for $($payloadFile.Name) in LM Studio $($profile.version)"
    }
    $duplicateIndex = $text.IndexOf(
        $prefix,
        $startIndex + $prefix.Length,
        [System.StringComparison]::Ordinal
    )
    if ($duplicateIndex -ge 0) {
        throw "The Chinese locale object for $($payloadFile.Name) is not unique"
    }
    $endIndex = Find-ObjectEnd -Text $text -StartIndex $startIndex
    $text = $text.Substring(0, $startIndex) + $payloadEmbedded + $text.Substring($endIndex + 1)
    $patchedNamespaces.Add($payloadFile.Name)
}

$deepOverlay = [System.IO.File]::ReadAllText($overlayPath, [System.Text.Encoding]::UTF8)
$text += "`r`n" + $deepOverlay

$destinationPath = if ($OutputPath) { [System.IO.Path]::GetFullPath($OutputPath) } else { $mainWindowPath }
$destinationDirectory = Split-Path -Parent $destinationPath
if (-not [System.IO.Directory]::Exists($destinationDirectory)) {
    [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
}
$candidatePath = if ($OutputPath) { $destinationPath } else { "$mainWindowPath.$($profile.profileId)-candidate-$PID.tmp" }
[System.IO.File]::WriteAllText($candidatePath, $text, [System.Text.UTF8Encoding]::new($false))
$patchedHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($patchedHash -ne $profile.patchedSha256.ToUpperInvariant()) {
    if ([System.IO.File]::Exists($candidatePath)) { Remove-Item -LiteralPath $candidatePath -Force }
    throw "Patched file verification failed for LM Studio $($profile.version). No installed file was changed. SHA256=$patchedHash"
}

if ($OutputPath) {
    Write-Output "Generated verified candidate for LM Studio $($profile.version): $destinationPath"
    Write-Output "Patched locale namespaces: $($patchedNamespaces -join ', ')"
    Write-Output "SHA256=$patchedHash"
    exit 0
}

$backupPath = "$mainWindowPath$($profile.backupSuffix)"
if ([System.IO.File]::Exists($backupPath)) {
    $existingBackupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($existingBackupHash -ne $profile.originalSha256.ToUpperInvariant()) {
        Remove-Item -LiteralPath $candidatePath -Force
        throw "Existing backup verification failed for LM Studio $($profile.version). Refusing to continue. SHA256=$existingBackupHash"
    }
} else {
    Copy-Item -LiteralPath $sourceMainWindowPath -Destination $backupPath
    $newBackupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($newBackupHash -ne $profile.originalSha256.ToUpperInvariant()) {
        Remove-Item -LiteralPath $candidatePath -Force
        Remove-Item -LiteralPath $backupPath -Force
        throw "New backup verification failed for LM Studio $($profile.version). SHA256=$newBackupHash"
    }
}

$swapPath = "$mainWindowPath.$($profile.profileId)-swap-$PID.tmp"
try {
    [System.IO.File]::Replace($candidatePath, $mainWindowPath, $swapPath)
    if ([System.IO.File]::Exists($swapPath)) { Remove-Item -LiteralPath $swapPath -Force }
    $installedHash = (Get-FileHash -LiteralPath $mainWindowPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($installedHash -ne $profile.patchedSha256.ToUpperInvariant()) {
        throw "Installed file verification failed. SHA256=$installedHash"
    }
} catch {
    if ([System.IO.File]::Exists($candidatePath)) { Remove-Item -LiteralPath $candidatePath -Force }
    if ([System.IO.File]::Exists($swapPath)) { Remove-Item -LiteralPath $swapPath -Force }
    if ([System.IO.File]::Exists($backupPath)) { Copy-Item -LiteralPath $backupPath -Destination $mainWindowPath -Force }
    throw
}

Write-Output "LM Studio $($profile.version) deep Chinese patch installed: $mainWindowPath"
if ($upgradingFromLegacy) { Write-Output 'Upgrade path: legacy safe patch -> versioned deep patch' }
Write-Output "Patched locale namespaces: $($patchedNamespaces -join ', ')"
Write-Output "SHA256=$installedHash"
