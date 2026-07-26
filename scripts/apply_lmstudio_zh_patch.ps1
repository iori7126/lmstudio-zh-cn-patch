param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [string]$OutputPath,

    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$ExpectedVersion = '0.4.20+1'
$ExpectedMainWindowSha256 = '5BEC77399EBD6C5C1B5426F506949C6D3202AAE0F9545B4E0BCCAB56EC7C788B'
$SafeV2Sha256 = 'D391E601C5E7C5E5C83E8C0D1C90311BC213CFEE0594E9C54C3A9F161A9E0FBA'
$ExpectedPatchedSha256 = 'A47D4DABEFA207A5699223B9A0BADF2CF9A29664154D8153EB6387BDEA285867'
$PatchSuffix = '.zh-cn-deep-0.4.20-1.bak'
$SafeV2BackupSuffix = '.zh-cn-enhanced-0.4.20-1.bak'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PackagedBaselineRoot = Join-Path $ProjectRoot 'baseline\zh-CN'
$PackagedPayloadRoot = Join-Path $ProjectRoot 'payload\zh-CN'
if (
    [System.IO.Directory]::Exists($PackagedBaselineRoot) -and
    [System.IO.Directory]::Exists($PackagedPayloadRoot)
) {
    $OfficialLocaleRoot = $PackagedBaselineRoot
    $PayloadRoot = $PackagedPayloadRoot
} else {
    $OfficialLocaleRoot = Join-Path $ProjectRoot 'data_in\official-localization\zh-CN'
    $PayloadRoot = Join-Path $ProjectRoot 'outputs\payload\zh-CN'
}

function Resolve-MainWindowPath {
    param([string]$InputPath)

    $resolved = [System.IO.Path]::GetFullPath($InputPath)
    if ([System.IO.File]::Exists($resolved)) {
        return $resolved
    }

    $candidate = Join-Path $resolved 'resources\app\.webpack\renderer\main_window.js'
    if ([System.IO.File]::Exists($candidate)) {
        return $candidate
    }

    throw "main_window.js was not found: $resolved"
}

function Find-ObjectEnd {
    param(
        [string]$Text,
        [int]$StartIndex
    )

    if ($Text[$StartIndex] -ne '{') {
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

$mainWindowPath = Resolve-MainWindowPath -InputPath $TargetPath
$backupPath = "$mainWindowPath$PatchSuffix"

if (-not $OutputPath) {
    $running = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^LM Studio$|^LMStudio$' }
    if ($running) {
        throw 'LM Studio is running. Close it completely before applying or restoring the patch.'
    }
}

if ($Restore) {
    if (-not [System.IO.File]::Exists($backupPath)) {
        throw "Backup file was not found: $backupPath"
    }
    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    if ($backupHash -ne $ExpectedMainWindowSha256) {
        throw "Backup verification failed. Refusing to restore SHA256=$backupHash"
    }
    $restoreTempPath = "$mainWindowPath.zh-cn-restore-$PID.tmp"
    $restoreSwapPath = "$mainWindowPath.zh-cn-restore-swap-$PID.tmp"
    Copy-Item -LiteralPath $backupPath -Destination $restoreTempPath -Force
    try {
        [System.IO.File]::Replace($restoreTempPath, $mainWindowPath, $restoreSwapPath)
    } finally {
        if ([System.IO.File]::Exists($restoreTempPath)) {
            Remove-Item -LiteralPath $restoreTempPath -Force
        }
        if ([System.IO.File]::Exists($restoreSwapPath)) {
            Remove-Item -LiteralPath $restoreSwapPath -Force
        }
    }
    $restoredHash = (Get-FileHash -LiteralPath $mainWindowPath -Algorithm SHA256).Hash
    Write-Output "Original file restored: $mainWindowPath"
    Write-Output "SHA256=$restoredHash"
    exit 0
}

$currentHash = (Get-FileHash -LiteralPath $mainWindowPath -Algorithm SHA256).Hash
$sourceMainWindowPath = $mainWindowPath
$upgradingFromSafeV2 = $false
if ($currentHash -eq $SafeV2Sha256) {
    $safeV2BackupPath = "$mainWindowPath$SafeV2BackupSuffix"
    if (-not [System.IO.File]::Exists($safeV2BackupPath)) {
        throw "The safe v2 patch is installed, but its original backup is missing: $safeV2BackupPath"
    }
    $safeV2BackupHash = (Get-FileHash -LiteralPath $safeV2BackupPath -Algorithm SHA256).Hash
    if ($safeV2BackupHash -ne $ExpectedMainWindowSha256) {
        throw "The safe v2 backup failed verification. Refusing to upgrade. SHA256=$safeV2BackupHash"
    }
    $sourceMainWindowPath = $safeV2BackupPath
    $upgradingFromSafeV2 = $true
} elseif ($currentHash -ne $ExpectedMainWindowSha256) {
    throw "Version check failed. This patch only supports LM Studio $ExpectedVersion. Current main_window.js SHA256=$currentHash"
}

$text = [System.IO.File]::ReadAllText($sourceMainWindowPath, [System.Text.Encoding]::UTF8)
$payloadFiles = Get-ChildItem -LiteralPath $PayloadRoot -Filter '*.json' -File | Sort-Object Name
$patchedNamespaces = New-Object System.Collections.Generic.List[string]

foreach ($payloadFile in $payloadFiles) {
    $officialPath = Join-Path $OfficialLocaleRoot $payloadFile.Name
    if (-not [System.IO.File]::Exists($officialPath)) {
        throw "Official Chinese baseline is missing: $officialPath"
    }

    $officialObject = Get-Content -LiteralPath $officialPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $payloadObject = Get-Content -LiteralPath $payloadFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $officialCompact = $officialObject | ConvertTo-Json -Compress -Depth 100
    $payloadCompact = $payloadObject | ConvertTo-Json -Compress -Depth 100
    # Locale objects are embedded inside a single-quoted JavaScript string
    # passed to JSON.parse(). Preserve JSON escapes through that outer layer.
    $payloadEmbedded = $payloadCompact.Replace('\', '\\').Replace("'", "\'")
    $payloadEmbedded = $payloadEmbedded.Replace(([char]0x2028).ToString(), '\\u2028')
    $payloadEmbedded = $payloadEmbedded.Replace(([char]0x2029).ToString(), '\\u2029')
    $prefixLength = [Math]::Min(120, $officialCompact.Length)
    $prefix = $officialCompact.Substring(0, $prefixLength)

    $startIndex = $text.IndexOf($prefix, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) {
        throw "Could not locate the Chinese locale object for $($payloadFile.Name)"
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
    $text = $text.Substring(0, $startIndex) +
        $payloadEmbedded +
        $text.Substring($endIndex + 1)
    $patchedNamespaces.Add($payloadFile.Name)
}

$deepOverlayPath = Join-Path $ProjectRoot 'deep\deep-overlay.js'
if (-not [System.IO.File]::Exists($deepOverlayPath)) {
    throw "Deep translation overlay is missing: $deepOverlayPath"
}
$deepOverlay = [System.IO.File]::ReadAllText(
    $deepOverlayPath,
    [System.Text.Encoding]::UTF8
)
$text += "`r`n" + $deepOverlay

$destinationPath = if ($OutputPath) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    $mainWindowPath
}

$destinationDirectory = Split-Path -Parent $destinationPath
if (-not [System.IO.Directory]::Exists($destinationDirectory)) {
    [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
}
$candidatePath = if ($OutputPath) {
    $destinationPath
} else {
    "$mainWindowPath.zh-cn-candidate-$PID.tmp"
}
[System.IO.File]::WriteAllText(
    $candidatePath,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

$patchedHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
if ($patchedHash -ne $ExpectedPatchedSha256) {
    if (-not $OutputPath -and [System.IO.File]::Exists($candidatePath)) {
        Remove-Item -LiteralPath $candidatePath -Force
    }
    throw "Patched file verification failed. No installed file was changed. SHA256=$patchedHash"
}

if (-not $OutputPath) {
    if ([System.IO.File]::Exists($backupPath)) {
        $existingBackupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
        if ($existingBackupHash -ne $ExpectedMainWindowSha256) {
            Remove-Item -LiteralPath $candidatePath -Force
            throw "Existing backup verification failed. Refusing to continue. SHA256=$existingBackupHash"
        }
    } else {
        Copy-Item -LiteralPath $sourceMainWindowPath -Destination $backupPath
    }

    try {
        $swapPath = "$mainWindowPath.zh-cn-swap-$PID.tmp"
        [System.IO.File]::Replace($candidatePath, $mainWindowPath, $swapPath)
        if ([System.IO.File]::Exists($swapPath)) {
            Remove-Item -LiteralPath $swapPath -Force
        }
    } catch {
        if ([System.IO.File]::Exists($candidatePath)) {
            Remove-Item -LiteralPath $candidatePath -Force
        }
        if ($swapPath -and [System.IO.File]::Exists($swapPath)) {
            Remove-Item -LiteralPath $swapPath -Force
        }
        if ([System.IO.File]::Exists($backupPath)) {
            Copy-Item -LiteralPath $backupPath -Destination $mainWindowPath -Force
        }
        throw
    }
}

Write-Output "Patched locale namespaces: $($patchedNamespaces -join ', ')"
if ($upgradingFromSafeV2) {
    Write-Output 'Upgrade path: safe v2 -> deep1.1'
}
Write-Output "Output: $destinationPath"
Write-Output "SHA256=$patchedHash"
