# Deterministic checks of a test workspace after a turn. The check types are documented in tests/jobsearch-kit/README.md.

# Files of the workspace (not .git) whose path relative to the workspace, with forward slashes, is -like the glob.
# "*" also matches "/", so "*/fit-analysis.md" finds the file in any application folder.
function Get-WorkspaceFiles {
  param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Glob, [switch]$Directories)
  $root = (Resolve-Path $Workspace).Path.TrimEnd('\') + '\'
  $glob = Expand-Placeholders $Glob $Workspace
  Get-ChildItem $Workspace -Recurse -Force -File:(-not $Directories) -Directory:$Directories |
    Where-Object { $_.FullName -notlike "$root.git\*" -and $_.FullName -ne "$root.git" } |
    Where-Object { ($_.FullName.Substring($root.Length) -replace '\\', '/') -like $glob }
}

function Get-RelativePath([string]$Workspace, [string]$Full) {
  $root = (Resolve-Path $Workspace).Path.TrimEnd('\') + '\'
  $Full.Substring($root.Length) -replace '\\', '/'
}

function New-CheckResult([string]$Name, [bool]$Pass, [string]$Expected, [string]$Actual, [bool]$Skipped = $false) {
  [pscustomobject]@{ Name = $Name; Pass = $Pass; Skipped = $Skipped; Expected = $Expected; Actual = $Actual }
}

function Get-PageCount {
  param([string]$Docx, [string]$OutDir)
  $out = & pwsh -NoProfile -File (Join-Path $script:PluginDir 'scripts\render-preview.ps1') -Docx $Docx -OutDir $OutDir 2>&1 | Out-String
  if ($out -match 'Word pages: (\d+)') { return [int]$Matches[1] }
  throw "render-preview.ps1 gave no page count: $out"
}

function Invoke-Check {
  <#
  .SYNOPSIS
    Runs one check object against the workspace and the turn's answer; returns a result with expected and actual.
  #>
  param([Parameter(Mandatory)]$Check, [Parameter(Mandatory)][string]$Workspace, [string]$Answer, [string]$FixtureDir, [string]$ScratchDir)
  $type = $Check.type
  $path = [string]$Check.path
  $name = if ($Check.name) { $Check.name } else { "$type $path$(if ($Check.pattern) { " /$($Check.pattern)/" })".Trim() }
  $files = if ($path) { @(Get-WorkspaceFiles $Workspace $path) } else { @() }
  $dirs = if ($path -and $type -in 'exists', 'absent', 'count') { @(Get-WorkspaceFiles $Workspace $path -Directories) } else { @() }
  $list = { param($f) if ($f.Count) { ($f | ForEach-Object { Get-RelativePath $Workspace $_.FullName }) -join ', ' } else { 'none' } }
  $opts = if ($Check.ignoreCase -eq $false) { 'None' } else { 'IgnoreCase' }
  switch ($type) {
    'exists' {
      $all = @($files) + @($dirs)
      return New-CheckResult $name ($all.Count -gt 0) "a file or folder matching $path" (& $list $all)
    }
    'absent' {
      $all = @($files) + @($dirs)
      return New-CheckResult $name ($all.Count -eq 0) "no file or folder matching $path" (& $list $all)
    }
    'count' {
      $all = @($files) + @($dirs)
      return New-CheckResult $name ($all.Count -eq [int]$Check.count) "$($Check.count) matching $path" "$($all.Count): $(& $list $all)"
    }
    { $_ -in 'unchanged', 'changed' } {
      $diff = git -C $Workspace status --porcelain -- $path 2>&1 | Out-String
      $changed = [bool]$diff.Trim()
      $want = $type -eq 'changed'
      $actual = if ($changed) { "changed: $($diff.Trim())" } else { 'unchanged since the seed commit' }
      return New-CheckResult $name ($changed -eq $want) "$path $type since the seed commit" $actual
    }
    { $_ -in 'contains', 'not-contains' } {
      if ($type -eq 'contains' -and -not $files.Count) { return New-CheckResult $name $false "a file matching $path containing /$($Check.pattern)/" 'no file matches' }
      $hits = @($files | Where-Object { [regex]::IsMatch((Get-Content $_.FullName -Raw), $Check.pattern, $opts) })
      if ($type -eq 'contains') {
        $miss = @($files | Where-Object { $_ -notin $hits })
        return New-CheckResult $name ($miss.Count -eq 0) "/$($Check.pattern)/ in every file matching $path" "missing in: $(& $list $miss)"
      }
      $snippets = $hits | ForEach-Object {
        $m = [regex]::Match((Get-Content $_.FullName -Raw), ".{0,60}$($Check.pattern).{0,60}", $opts)
        "$(Get-RelativePath $Workspace $_.FullName): ...$($m.Value)..."
      }
      return New-CheckResult $name ($hits.Count -eq 0) "no /$($Check.pattern)/ in $path" $(if ($hits.Count) { $snippets -join ' | ' } else { 'not found' })
    }
    { $_ -in 'answer-contains', 'answer-not-contains' } {
      $m = [regex]::Match($Answer, ".{0,60}$($Check.pattern).{0,60}", $opts)
      $want = $type -eq 'answer-contains'
      $actual = if ($m.Success) { "found: ...$($m.Value)..." } else { 'not found' }
      return New-CheckResult $name ($m.Success -eq $want) "$(if (-not $want) { 'no ' })/$($Check.pattern)/ in the answer" $actual
    }
    'lint' {
      if (-not $files.Count) { return New-CheckResult $name $false "a file matching $path that passes cv.js --lint" 'no file matches' }
      $out = & node (Join-Path $script:PluginDir 'scripts\cv.js') --lint @($files.FullName) --root $Workspace 2>&1 | Out-String
      return New-CheckResult $name ($LASTEXITCODE -eq 0 -and $out -notmatch 'WARNING') "cv.js --lint passes for $(& $list $files)" $out.Trim()
    }
    'pages' {
      $reason = Test-Requirement 'word'
      if ($reason) { return New-CheckResult $name $true "$path has at most $($Check.max) page(s)" "skipped: $reason" $true }
      if (-not $files.Count) { return New-CheckResult $name $false "a .docx matching $path" 'no file matches' }
      $counts = foreach ($f in $files) { "$(Get-RelativePath $Workspace $f.FullName)=$(Get-PageCount $f.FullName (Join-Path $ScratchDir 'preview'))" }
      $bad = @($counts | Where-Object { [int]($_ -replace '.*=', '') -gt [int]$Check.max })
      return New-CheckResult $name ($bad.Count -eq 0) "at most $($Check.max) page(s) in $path" ($counts -join ', ')
    }
    'ignored' {
      $all = @($files)
      if (-not $all.Count) { return New-CheckResult $name $false "a file matching $path, ignored by git" 'no file matches' }
      $tracked = @($all | Where-Object { $null = git -C $Workspace check-ignore -q $_.FullName 2>&1; $LASTEXITCODE -ne 0 })
      return New-CheckResult $name ($tracked.Count -eq 0) "every file matching $path ignored by git" "not ignored: $(& $list $tracked)"
    }
    'script' {
      $file = Join-Path $FixtureDir $Check.file
      $answerFile = Join-Path $ScratchDir 'answer.md'
      Set-Content -LiteralPath $answerFile -Value $Answer -Encoding UTF8
      $out = & pwsh -NoProfile -File $file -Workspace $Workspace -AnswerFile $answerFile 2>&1 | Out-String
      return New-CheckResult $name ($LASTEXITCODE -eq 0) "$($Check.file) exits with 0" $out.Trim()
    }
    default { return New-CheckResult $name $false "a known check type" "unknown check type '$type'" }
  }
}

function Invoke-TurnChecks {
  param([Parameter(Mandatory)]$Turn, [Parameter(Mandatory)][string]$Workspace, [string]$Answer, [string]$FixtureDir, [string]$ScratchDir)
  if (-not $Turn.ChecksFile) { return @() }
  $checks = @(Get-Content $Turn.ChecksFile -Raw | ConvertFrom-Json)
  foreach ($c in $checks) {
    try { Invoke-Check -Check $c -Workspace $Workspace -Answer $Answer -FixtureDir $FixtureDir -ScratchDir $ScratchDir }
    catch { New-CheckResult "$($c.type) $($c.path)" $false 'the check runs' "error: $($_.Exception.Message)" }
  }
}
