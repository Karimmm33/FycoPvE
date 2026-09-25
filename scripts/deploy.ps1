<#
.SYNOPSIS
    Copy the addon from this project into a live WoW client for testing.

.DESCRIPTION
    This project is the source of truth. The copy inside the WoW client is
    disposable: deploy overwrites it, so never edit the client copy and expect
    the change to survive.

    Only the files the addon actually needs are sent. Everything that makes
    this a development project -- .git, docs, scripts, AGENTS.md, CLAUDE.md --
    stays behind, so the client folder looks exactly like what a user unzips.

    Data and Modules are MIRRORED, so a file deleted here is deleted
    there too. That is what stops a module you removed from lingering in the
    client and loading from a stale .toc entry.

.PARAMETER ClientPath
    The addon folder inside the client. Defaults to the Frostmourne install.

.EXAMPLE
    .\scripts\deploy.ps1
    .\scripts\deploy.ps1 -WhatIf
    .\scripts\deploy.ps1 -ClientPath "C:\Games\WoW\Interface\AddOns\FycoPvE"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ClientPath = "D:\Whitemane\Frostmourne\FrostmourneRebuffed\Interface\AddOns\FycoPvE"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# What ships. Anything not named here stays in the project.
$rootFiles  = @("FycoPvE.toc", "Core.lua", "Widgets.lua", "Sources.lua", "README.md", "LICENSE")
$mirrorDirs = @("Data", "Modules")

Write-Host "source : $root"
Write-Host "target : $ClientPath"

# --- safety ------------------------------------------------------------------
# The directory mirror deletes files at the destination that are not at the
# source. Pointed at the wrong folder that is destructive, so refuse to mirror
# into anything that is not either new or already this addon.
if (Test-Path $ClientPath) {
    if (-not (Test-Path (Join-Path $ClientPath "FycoPvE.toc"))) {
        throw "Refusing to deploy: '$ClientPath' exists but holds no FycoPvE.toc, so it does not look like this addon's folder."
    }
    if ((Split-Path $ClientPath -Leaf) -ne "FycoPvE") {
        throw "Refusing to deploy: the target folder must be named exactly 'FycoPvE' (WoW matches the folder name to FycoPvE.toc), but it is '$(Split-Path $ClientPath -Leaf)'."
    }
} elseif ($PSCmdlet.ShouldProcess($ClientPath, "create addon folder")) {
    New-Item -ItemType Directory -Path $ClientPath -Force | Out-Null
}

# --- root files --------------------------------------------------------------
foreach ($f in $rootFiles) {
    $src = Join-Path $root $f
    if (-not (Test-Path $src)) { throw "missing from project: $f" }
    if ($PSCmdlet.ShouldProcess((Join-Path $ClientPath $f), "copy")) {
        Copy-Item $src -Destination (Join-Path $ClientPath $f) -Force
    }
    Write-Host "  copied   $f"
}

# --- mirrored directories ----------------------------------------------------
foreach ($d in $mirrorDirs) {
    $src = Join-Path $root $d
    $dst = Join-Path $ClientPath $d
    if (-not (Test-Path $src)) { throw "missing from project: $d\" }

    if ($PSCmdlet.ShouldProcess($dst, "mirror")) {
        # robocopy exit codes under 8 are success; 8 and above is a real failure
        robocopy $src $dst /MIR /NJH /NJS /NDL /NP /NFL | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $d (exit $LASTEXITCODE)" }
    }
    Write-Host "  mirrored $d\  ($((Get-ChildItem $src -File -Recurse).Count) files)"
}

Write-Host ""
Write-Host "Deployed. In game: /reload   (Plates changes always need one.)" -ForegroundColor Green
