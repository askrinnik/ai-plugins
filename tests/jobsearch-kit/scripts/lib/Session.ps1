# Test workspaces and headless Claude Code sessions for the jobsearch-kit skill tests.

$script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:TestsDir = Join-Path $script:Repo 'tests\jobsearch-kit'
$script:Config = Get-Content (Join-Path $script:TestsDir 'config.json') -Raw | ConvertFrom-Json
$script:PluginDir = Join-Path $script:Repo $script:Config.plugin
$script:SeedDir = Join-Path $script:Repo $script:Config.seed
$script:TempRoot = Join-Path ([IO.Path]::GetTempPath()) 'jobsearch-tests'

# Tools of a test session unless fixture.json sets "allowedTools". Every tool a skill may use must be here: a
# headless session does not ask, it gets a denial.
$script:DefaultAllowedTools = @('Read', 'Write', 'Edit', 'Glob', 'Grep', 'Skill', 'Bash', 'PowerShell', 'TodoWrite', 'WebSearch', 'WebFetch')

function Get-PluginVersion {
  (Get-Content (Join-Path $script:PluginDir '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json).version
}

function Read-Fixture {
  <#
  .SYNOPSIS
    Reads a fixture folder: turns, checks, ground truths and fixture.json with defaults.
  #>
  param([Parameter(Mandatory)][string]$Dir)
  $name = Split-Path $Dir -Leaf
  $json = Join-Path $Dir 'fixture.json'
  $cfg = if (Test-Path $json) { Get-Content $json -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  $turnFiles = @(Get-ChildItem (Join-Path $Dir 'turns') -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object Name)
  if (-not $turnFiles.Count) {
    $prompt = Join-Path $Dir 'prompt.txt'
    if (-not (Test-Path $prompt)) { throw "Fixture '$name' has neither prompt.txt nor turns\*.txt" }
    $turnFiles = @(Get-Item $prompt)
  }
  $turns = for ($i = 0; $i -lt $turnFiles.Count; $i++) {
    $n = '{0:D2}' -f ($i + 1)
    $gt = Join-Path $Dir "ground-truth\$n.md"
    if ($i -eq 0 -and -not (Test-Path $gt) -and (Test-Path (Join-Path $Dir 'ground-truth.md'))) { $gt = Join-Path $Dir 'ground-truth.md' }
    [pscustomobject]@{
      N           = $n
      PromptFile  = $turnFiles[$i].FullName
      ChecksFile  = $(if (Test-Path (Join-Path $Dir "checks\$n.json")) { Join-Path $Dir "checks\$n.json" })
      GroundTruth = $(if (Test-Path $gt) { $gt })
    }
  }
  $judge = if ($cfg.judge) { $cfg.judge } else { [pscustomobject]@{} }
  [pscustomobject]@{
    Name           = $name
    Dir            = $Dir
    Description    = [string]$cfg.description
    Repetitions    = $(if ($cfg.repetitions) { [int]$cfg.repetitions } else { 1 })
    AllowedTools   = $(if ($cfg.allowedTools) { @($cfg.allowedTools) } else { $script:DefaultAllowedTools + @($cfg.addAllowedTools | Where-Object { $_ }) })
    Slow           = [bool]$cfg.slow
    Requires       = @($cfg.requires | Where-Object { $_ })
    TimeoutMinutes = $(if ($cfg.timeoutMinutes) { [int]$cfg.timeoutMinutes } else { 20 })
    SeedCopy       = @($cfg.seedCopy | Where-Object { $_ })
    SeedRemove     = @($cfg.seedRemove | Where-Object { $_ })
    JudgeFiles     = @($judge.files | Where-Object { $_ })
    MinScore       = $judge.minScore
    Turns          = @($turns)
  }
}

function Test-Requirement {
  <#
  .SYNOPSIS
    Returns $null when the requirement is met, else the reason to skip ("word", "whisper").
  #>
  param([string]$Name)
  switch ($Name) {
    'word' { if (-not (Get-Item 'Registry::HKEY_CLASSES_ROOT\Word.Application' -ErrorAction SilentlyContinue)) { return 'Microsoft Word is not installed' } }
    'whisper' {
      $dir = if ($env:JOBSEARCH_WHISPER) { $env:JOBSEARCH_WHISPER } else { [Environment]::GetEnvironmentVariable('JOBSEARCH_WHISPER', 'User') }
      if (-not $dir) { $dir = Join-Path $env:LOCALAPPDATA 'ai-plugins\jobsearch-kit\whisper' }
      if (-not (Test-Path (Join-Path $dir '.venv\Scripts\python.exe'))) { return "no whisper environment in $dir (JOBSEARCH_WHISPER)" }
    }
    default { return "unknown requirement '$Name'" }
  }
  $null
}

function Expand-Placeholders {
  param([string]$Text, [string]$Workspace)
  $now = Get-Date
  $Text.Replace('{{today}}', $now.ToString('yyyy-MM-dd')).Replace('{{date}}', $now.ToString('yyyy_MM_dd')).Replace('{{workspace}}', ($Workspace -replace '\\', '/'))
}

function New-TestWorkspace {
  <#
  .SYNOPSIS
    Creates a fresh workspace for one fixture repetition: the seed, the fixture's seed files, git init, one commit.
  .DESCRIPTION
    Order: copy the seed workspace (config.json "seed"); remove "seedRemove" paths; copy "seedCopy" items
    ({ from: <path relative to the repository>, to: <path relative to the workspace> }; placeholders allowed in
    "to"); copy the fixture's seed\ folder over it; apply seed.diff with git apply; commit everything.
  #>
  param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$Path)
  if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
  New-Item -ItemType Directory -Force $Path | Out-Null
  Copy-Item (Join-Path $script:SeedDir '*') $Path -Recurse -Force
  Copy-Item (Join-Path $script:SeedDir '.gitignore') $Path -Force -ErrorAction SilentlyContinue
  foreach ($r in $Fixture.SeedRemove) { Remove-Item (Join-Path $Path $r) -Recurse -Force -ErrorAction SilentlyContinue }
  foreach ($c in $Fixture.SeedCopy) {
    $from = Join-Path $script:Repo $c.from
    $to = Join-Path $Path (Expand-Placeholders $c.to $Path)
    if (-not (Test-Path $from)) { throw "seedCopy: $($c.from) does not exist" }
    if ((Get-Item $from).PSIsContainer) {
      New-Item -ItemType Directory -Force $to | Out-Null
      Copy-Item (Join-Path $from '*') $to -Recurse -Force
    }
    else {
      New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
      Copy-Item $from $to -Force
    }
  }
  $seed = Join-Path $Fixture.Dir 'seed'
  if (Test-Path $seed) { Copy-Item (Join-Path $seed '*') $Path -Recurse -Force }
  $null = git -C $Path init -q -b main 2>&1
  $diff = Join-Path $Fixture.Dir 'seed.diff'
  if (Test-Path $diff) {
    $out = git -C $Path apply --whitespace=nowarn $diff 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git apply seed.diff failed: $out" }
  }
  $null = git -C $Path add -A 2>&1
  $null = git -C $Path -c user.name=jobsearch-tests -c user.email=tests@example.com commit -q -m 'Seed workspace' 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git commit of the seed workspace failed in $Path" }
}

function Get-SessionArguments {
  param([Parameter(Mandatory)]$Fixture, [string]$Model, [string]$Effort, [string]$ResumeId)
  # The user's own CLAUDE.md would change the session (language, private rules): exclude it. User settings
  # (installed plugins, hooks, permissions) are left out with --setting-sources.
  $userMd = (Join-Path $HOME '.claude\CLAUDE.md') -replace '\\', '/'
  $settings = @{ claudeMdExcludes = @($userMd) } | ConvertTo-Json -Compress
  $a = @('-p', '--output-format', 'json', '--model', $Model,
    '--setting-sources', 'project,local', '--settings', $settings, '--strict-mcp-config',
    '--plugin-dir', $script:PluginDir, '--add-dir', $script:PluginDir,
    '--allowedTools', ($Fixture.AllowedTools -join ','))
  if ($Effort) { $a += @('--effort', $Effort) }
  if ($ResumeId) { $a += @('--resume', $ResumeId) }
  $a
}

function Invoke-Claude {
  <#
  .SYNOPSIS
    Runs claude with the prompt on stdin in a clean environment; returns exit code, stdout, stderr, seconds.
  .DESCRIPTION
    The variables of a hosting Claude Code session (CLAUDECODE, CLAUDE_CODE_*, ...) are removed, so the test
    session behaves like one started from a terminal. JOBSEARCH_* variables pass through.
  #>
  param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][string]$WorkingDirectory, [int]$TimeoutMinutes = 20)
  $psi = [Diagnostics.ProcessStartInfo]::new((Get-Command claude -CommandType Application | Select-Object -First 1).Source)
  foreach ($x in $Arguments) { $psi.ArgumentList.Add($x) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $psi.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
  foreach ($k in @($psi.Environment.Keys)) {
    if ($k -match '^(CLAUDECODE|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID|CLAUDE_PREVIEW_)') { [void]$psi.Environment.Remove($k) }
  }
  foreach ($k in 'JOBSEARCH_WHISPER', 'JOBSEARCH_DEPS') {
    if (-not $psi.Environment[$k]) {
      $v = [Environment]::GetEnvironmentVariable($k, 'User')
      if ($v) { $psi.Environment[$k] = $v }
    }
  }
  $started = Get-Date
  $p = [Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEndAsync()
  $stderr = $p.StandardError.ReadToEndAsync()
  $p.StandardInput.Write($Prompt)
  $p.StandardInput.Close()
  if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
    $p.Kill($true)
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = -1; Out = $stdout.Result; Err = "Timed out after $TimeoutMinutes minutes. $($stderr.Result)"; Seconds = ((Get-Date) - $started).TotalSeconds }
  }
  [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $stdout.Result; Err = $stderr.Result; Seconds = ((Get-Date) - $started).TotalSeconds }
}

function Find-Transcript {
  param([Parameter(Mandatory)][string]$SessionId)
  Get-ChildItem (Join-Path $HOME '.claude\projects') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "$SessionId.jsonl" } | Where-Object { Test-Path $_ } | Select-Object -First 1
}
