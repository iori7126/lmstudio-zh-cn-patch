param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [switch]$Restore,

    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    $quotedScript = '"{0}"' -f $PSCommandPath
    $quotedTarget = '"{0}"' -f $TargetPath
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -TargetPath $quotedTarget -Pause"
    if ($Restore) {
        $arguments += ' -Restore'
    }

    try {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList $arguments `
            -Wait `
            -PassThru
        exit $process.ExitCode
    } catch {
        Write-Host 'Administrator permission was not granted. No files were modified.' -ForegroundColor Red
        exit 1
    }
}

$coreScript = Join-Path $PSScriptRoot 'apply_lmstudio_zh_patch.ps1'
$exitCode = 0
try {
    if ($Restore) {
        & $coreScript -TargetPath $TargetPath -Restore
    } else {
        & $coreScript -TargetPath $TargetPath
    }
} catch {
    Write-Host "Patch error: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

if ($Pause) {
    [void](Read-Host 'Press Enter to close')
}
exit $exitCode
