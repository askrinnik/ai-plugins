<#
.SYNOPSIS
  Installs the npm packages of the jobsearch-kit scripts outside the plugin.

.DESCRIPTION
  The plugin folder is replaced on every plugin install, and a workspace may live in a synced folder such as
  OneDrive, so node_modules is kept elsewhere:

    pwsh -File scripts\install-deps.ps1 [-DepsDir <folder>]

  The default DepsDir is the JOBSEARCH_DEPS environment variable, else %LOCALAPPDATA%\ai-plugins\jobsearch-kit.
  Copies package.json and package-lock.json to DepsDir and runs "npm ci" there. The scripts load packages from
  DepsDir\node_modules (see workspace.js). If you choose another DepsDir, set JOBSEARCH_DEPS to it.
  Run it on a new computer and after a plugin update that changes package.json.
#>
param(
  [string]$DepsDir = $(if ($env:JOBSEARCH_DEPS) { $env:JOBSEARCH_DEPS } else { Join-Path $env:LOCALAPPDATA 'ai-plugins\jobsearch-kit' })
)
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force $DepsDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'package.json'), (Join-Path $PSScriptRoot 'package-lock.json') $DepsDir -Force
Push-Location $DepsDir
try {
  & npm ci --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
}
finally {
  Pop-Location
}
Write-Output "Packages installed in $(Join-Path $DepsDir 'node_modules')"
