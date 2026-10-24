param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$BundlePath
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $RepoRoot 'test-artifacts\patch-flow-0.4.26'
$renderer = Join-Path $testRoot 'resources\app\.webpack\renderer'
$fixture = Join-Path $renderer 'main_window.js'
$script = Join-Path $RepoRoot 'scripts\apply_lmstudio_zh_patch.ps1'
$profile = Get-Content -LiteralPath (Join-Path $RepoRoot 'versions\0.4.26+4\profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json

if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
New-Item -ItemType Directory -Path $renderer -Force | Out-Null
Copy-Item -LiteralPath $BundlePath -Destination $fixture
$originalHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToUpperInvariant()
if ($originalHash -ne $profile.originalSha256.ToUpperInvariant()) { throw "Fixture original hash mismatch: $originalHash" }

$candidate = Join-Path $testRoot 'candidate.js'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $testRoot -OutputPath $candidate
if ($LASTEXITCODE -ne 0) { throw 'Candidate generation failed' }
$candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToUpperInvariant()
if ($candidateHash -ne $profile.patchedSha256.ToUpperInvariant()) { throw "Candidate hash mismatch: $candidateHash" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $testRoot
if ($LASTEXITCODE -ne 0) { throw 'Fixture install failed' }
$installedHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToUpperInvariant()
if ($installedHash -ne $profile.patchedSha256.ToUpperInvariant()) { throw "Installed fixture hash mismatch: $installedHash" }
$backup = "$fixture$($profile.backupSuffix)"
if (-not (Test-Path -LiteralPath $backup)) { throw "Backup was not created: $backup" }
$backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpperInvariant()
if ($backupHash -ne $profile.originalSha256.ToUpperInvariant()) { throw "Backup hash mismatch: $backupHash" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $testRoot
if ($LASTEXITCODE -ne 0) { throw 'Repeated install was not safely accepted' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $testRoot -Restore
if ($LASTEXITCODE -ne 0) { throw 'Fixture restore failed' }
$restoredHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToUpperInvariant()
if ($restoredHash -ne $profile.originalSha256.ToUpperInvariant()) { throw "Restored fixture hash mismatch: $restoredHash" }

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$restoreOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $testRoot -Restore 2>&1 | Out-String
$restoreExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($restoreExitCode -eq 0 -or $restoreOutput -notmatch 'not a recognized patched file') { throw 'Repeated restore was not safely rejected' }

$unknown = Join-Path $testRoot 'unknown'
New-Item -ItemType Directory -Path (Join-Path $unknown 'resources\app\.webpack\renderer') -Force | Out-Null
$unknownPath = Join-Path $unknown 'resources\app\.webpack\renderer\main_window.js'
Copy-Item -LiteralPath $BundlePath -Destination $unknownPath
Add-Content -LiteralPath $unknownPath -Value 'x' -NoNewline
$unknownBefore = (Get-FileHash -LiteralPath $unknownPath -Algorithm SHA256).Hash
$ErrorActionPreference = 'Continue'
$unknownOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetPath $unknown 2>&1 | Out-String
$unknownExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($unknownExitCode -eq 0 -or $unknownOutput -notmatch 'unknown main_window') { throw 'Unknown version was not rejected' }
$unknownAfter = (Get-FileHash -LiteralPath $unknownPath -Algorithm SHA256).Hash
if ($unknownBefore -ne $unknownAfter) { throw 'Unknown version was modified' }

Write-Output "PATCH_FLOW_OK original=$originalHash patched=$candidateHash restored=$restoredHash"

