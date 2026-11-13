<#
.SYNOPSIS
    Registers the UWP build output as a loose (unsigned) package on this PC.

.DESCRIPTION
    Needs Windows Developer Mode. Copies the files listed in the build's
    keeperfx.build.appxrecipe into a layout folder, replaces any earlier
    registration and registers the layout. Start KeeperFX from the Start menu.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build\uwp\register-layout.ps1
#>
param(
    [string]$BuildDir = (Join-Path $PSScriptRoot "..\..\out\build\uwp-x64\RelWithDebInfo"),
    [string]$Layout   = (Join-Path $PSScriptRoot "..\..\out\keeperfx-layout")
)
$ErrorActionPreference = "Stop"
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
$Layout   = [IO.Path]::GetFullPath($Layout)

$recipe = Join-Path $BuildDir "keeperfx.build.appxrecipe"
if (-not (Test-Path $recipe)) { throw "$recipe not found; build the uwp-x64 preset first." }

Get-AppxPackage KeeperFX.DungeonKeeper | Remove-AppxPackage
if (Test-Path $Layout) { Remove-Item $Layout -Recurse -Force }

[xml]$x = Get-Content $recipe
$x.Project.ItemGroup | ForEach-Object { $_.ChildNodes } |
    Where-Object { $_.LocalName -in 'AppXManifest', 'AppxPackagedFile' } |
    ForEach-Object {
        $dest = Join-Path $Layout $_.PackagePath
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $_.Include $dest
    }

Add-AppxPackage -Register (Join-Path $Layout "AppxManifest.xml")
$pkg = Get-AppxPackage KeeperFX.DungeonKeeper
Write-Host "Registered $($pkg.PackageFamilyName)"
Write-Host "Game folder: $env:LOCALAPPDATA\Packages\$($pkg.PackageFamilyName)\LocalState\KeeperFX"
