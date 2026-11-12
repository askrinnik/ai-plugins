# Settings of the benchmark: the repository under test is the git repository of the current folder, never the folder
# of these scripts (they run from the plugin cache). The benchmark folder (fixtures, run history, runs, reports)
# stays in that repository; its path is the optional key "dir" of harness-quality-check.config.json in the
# repository root, default .ai/benchmarks/harness.

$script:harnessSettingKeys = @('dir')
$script:defaultHarnessDir = '.ai/benchmarks/harness'

function Get-HarnessRepoRoot {
  $root = & git rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $root) { throw "The current folder ($((Get-Location).Path)) is not inside a git repository. Run the benchmark from the repository under test." }
  [IO.Path]::GetFullPath(([string]($root | Select-Object -First 1)).Trim())
}

function Get-HarnessDir {
  <#
  .SYNOPSIS
    Returns the benchmark folder relative to the repository root, with forward slashes: the -Dir parameter, else the
    "dir" key of harness-quality-check.config.json, else .ai/benchmarks/harness. A bad settings file stops the run with
    a message that names the file and the key.
  #>
  param([Parameter(Mandatory)][string]$RepoRoot, [string]$Dir)
  if (-not $Dir) {
    $file = Join-Path $RepoRoot 'harness-quality-check.config.json'
    $Dir = $script:defaultHarnessDir
    if (Test-Path -LiteralPath $file) {
      try { $cfg = [IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { throw "$file is not valid JSON: $($_.Exception.Message)" }
      if ($cfg -isnot [pscustomobject]) { throw "$file must hold a JSON object." }
      foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -notin $script:harnessSettingKeys) { throw "$file : unknown key '$($p.Name)'; the keys are $($script:harnessSettingKeys -join ', ')." }
        if ($p.Value -isnot [string] -or -not $p.Value) { throw "$file : key '$($p.Name)' must be a non-empty text." }
      }
      if ($cfg.dir) { $Dir = $cfg.dir }
    }
  }
  if ([IO.Path]::IsPathRooted($Dir)) { throw "The benchmark folder must be relative to the repository root; found '$Dir'." }
  ($Dir -replace '\\', '/').TrimEnd('/')
}
