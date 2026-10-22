# Settings of the profiler: three JSON layers, each overriding the previous one per key. The defaults file ships with
# the skill, the user file lives in the Claude config folder and the repository file in the repository root. Every
# key is optional in the user and repository files and a missing file is not an error.
. (Join-Path $PSScriptRoot 'Cost.ps1')

$script:settingKeys = 'resultsDir', 'baseBranch', 'workItemPattern', 'workItemCommandPattern', 'lanePlanGlob', 'excludeSessionManifests', 'activityRules', 'costWeights'

function Assert-RegexText([string]$Text, [string]$What, [string]$File) {
  try { $null = [regex]::new($Text) } catch { throw "$File : $What is not a valid regular expression ('$Text'): $($_.Exception.Message)" }
}

function ConvertTo-TextList($Value, [string]$What, [string]$File) {
  $list = @()
  foreach ($v in @($Value)) {
    if ($v -isnot [string]) { throw "$File : $What must be a text or a list of texts." }
    if ($v) { $list += $v }
  }
  , $list
}

function Read-SettingsFile {
  <#
  .SYNOPSIS
    Reads one settings file into an object holding only the keys it sets, or returns $null when the file is missing.
  .DESCRIPTION
    An unknown key, a value of the wrong type and an invalid regular expression stop the run with a message that names
    the file and the key, so a typo is not silently ignored.
  #>
  param([Parameter(Mandatory)][string]$File)
  if (-not (Test-Path $File)) { return $null }
  try { $cfg = [IO.File]::ReadAllText($File) | ConvertFrom-Json } catch { throw "$File is not valid JSON: $($_.Exception.Message)" }
  if ($cfg -isnot [pscustomobject]) { throw "$File must hold a JSON object." }
  $out = [ordered]@{}
  foreach ($p in $cfg.PSObject.Properties) {
    $k = $p.Name; $v = $p.Value
    if ($k -notin $script:settingKeys) { throw "$File : unknown setting '$k'; the settings are $($script:settingKeys -join ', ')." }
    switch ($k) {
      { $_ -in 'resultsDir', 'baseBranch', 'lanePlanGlob', 'workItemCommandPattern' } {
        if ($v -isnot [string]) { throw "$File : '$k' must be a text." }
        if ($k -eq 'workItemCommandPattern' -and $v) { Assert-RegexText $v $k $File }
        if ($k -eq 'resultsDir' -and -not $v) { throw "$File : 'resultsDir' must not be empty." }
        $out[$k] = $v
      }
      'workItemPattern' {
        $list = ConvertTo-TextList $v $k $File
        foreach ($t in $list) { Assert-RegexText $t $k $File }
        $out[$k] = $list
      }
      'excludeSessionManifests' { $out[$k] = ConvertTo-TextList $v $k $File }
      'activityRules' {
        $rules = @()
        foreach ($r in @($v)) {
          if ($r -isnot [pscustomobject] -or -not $r.pattern -or -not $r.category -or $r.pattern -isnot [string] -or $r.category -isnot [string]) {
            throw "$File : each activity rule needs a text 'pattern' and a text 'category'."
          }
          Assert-RegexText $r.pattern 'an activity rule pattern' $File
          $rules += [pscustomobject]@{ Pattern = [string]$r.pattern; Category = [string]$r.category }
        }
        $out[$k] = $rules
      }
      'costWeights' {
        if ($v -isnot [pscustomobject]) { throw "$File : 'costWeights' must be an object." }
        $out[$k] = $v
      }
    }
  }
  [pscustomobject]$out
}

function Get-ProfileSettings {
  <#
  .SYNOPSIS
    Merges the defaults, user and repository settings files, applies the cost weights and returns the settings.
  .DESCRIPTION
    Later layers override earlier ones per key; a list replaces the earlier list as a whole, and costWeights are
    merged weight by weight. The defaults file must exist.
  #>
  param([Parameter(Mandatory)][string]$DefaultsFile, [string]$UserFile, [string]$RepoFile)
  if (-not (Test-Path $DefaultsFile)) { throw "Defaults file not found: $DefaultsFile" }
  $s = [ordered]@{
    ResultsDir = '.ai/benchmarks/sessions'; BaseBranch = ''; WorkItemPatterns = @('^#(\d+)'); WorkItemCommandPattern = ''
    LanePlanGlob = ''; ExcludeSessionManifests = @(); ActivityRules = @(); Sources = @()
  }
  Reset-CostWeights
  foreach ($file in $DefaultsFile, $UserFile, $RepoFile) {
    if (-not $file) { continue }
    $cfg = Read-SettingsFile $file
    if ($null -eq $cfg) { continue }
    $s.Sources += $file
    foreach ($p in $cfg.PSObject.Properties) {
      switch ($p.Name) {
        'resultsDir' { $s.ResultsDir = $p.Value }
        'baseBranch' { $s.BaseBranch = $p.Value }
        'workItemPattern' { $s.WorkItemPatterns = @($p.Value) }
        'workItemCommandPattern' { $s.WorkItemCommandPattern = $p.Value }
        'lanePlanGlob' { $s.LanePlanGlob = $p.Value }
        'excludeSessionManifests' { $s.ExcludeSessionManifests = @($p.Value) }
        'activityRules' { $s.ActivityRules = @($p.Value) }
        'costWeights' { try { Set-CostWeights $p.Value } catch { throw "$file : $($_.Exception.Message)" } }
      }
    }
  }
  [pscustomobject]$s
}

function Find-WorkItem {
  <#
  .SYNOPSIS
    Returns the work item id found in a text by the first matching pattern: its first group, or the whole match
    when the pattern has no group; empty when none matches.
  #>
  param([string]$Text, [string[]]$Patterns)
  if (-not $Text) { return '' }
  foreach ($p in $Patterns) {
    $m = [regex]::Match($Text, $p)
    if (-not $m.Success) { continue }
    $v = if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success -and $m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Value }
    if ($v) { return $v }
  }
  ''
}
