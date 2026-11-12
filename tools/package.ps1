# Builds the CurseForge release zip: .release/CraftmansHelper-<version>.zip
# The zip contains a single top-level CraftmansHelper/ folder, as WoW addon zips must.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File tools\package.ps1

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path $PSScriptRoot -Parent
$addon = Join-Path $root "CraftmansHelper"
$toc = Join-Path $addon "CraftmansHelper.toc"

$versionLine = Select-String -Path $toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw "No '## Version:' line in $toc" }
$version = $versionLine.Matches[0].Groups[1].Value
if ($version -like "*@*") { throw "TOC version is a placeholder ($version); set a real version first." }

$outDir = Join-Path $root ".release"
New-Item -ItemType Directory -Force $outDir | Out-Null
$zipPath = Join-Path $outDir "CraftmansHelper-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Write entries with forward slashes (Compress-Archive on PowerShell 5.1 uses backslashes,
# which break extraction on non-Windows tools).
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $count = 0
    Get-ChildItem $addon -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($addon.Length + 1) -replace '\\', '/'
        $entry = "CraftmansHelper/$relative"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $count++
    }
} finally {
    $zip.Dispose()
}

$sizeKb = [math]::Round((Get-Item $zipPath).Length / 1KB)
Write-Host "Built $zipPath ($count files, $sizeKb KB)" -ForegroundColor Green
