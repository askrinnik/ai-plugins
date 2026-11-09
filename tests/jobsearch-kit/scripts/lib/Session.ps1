# Test workspaces and headless sessions (Claude Code or GitHub Copilot CLI) for the jobsearch-kit skill tests.

$script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:TestsDir = Join-Path $script:Repo 'tests\jobsearch-kit'
$script:Config = Get-Content (Join-Path $script:TestsDir 'config.json') -Raw | ConvertFrom-Json
$script:PluginDir = Join-Path $script:Repo $script:Config.plugin
$script:SeedDir = Join-Path $script:Repo $script:Config.seed
$script:TempRoot = Join-Path ([IO.Path]::GetTempPath()) 'jobsearch-tests'
$script:Clis = @('claude', 'copilot')

# The Copilot CLI home of the test sessions (config, session state). Run-Tests.ps1 sets one per run, so that the
# developer's own Copilot setup (installed plugins, MCP servers, user instructions) stays out of the sessions.
$script:CopilotHome = Join-Path $script:TempRoot 'copilot-home'

# Tools of a test session unless fixture.json sets "allowedTools". Every tool a skill may use must be here: a
# headless session does not ask, it gets a denial. The names are Claude Code tool names; a Copilot session gets the
# tools of $script:CopilotToolMap.
$script:DefaultAllowedTools = @('Read', 'Write', 'Edit', 'Glob', 'Grep', 'Skill', 'Bash', 'PowerShell', 'TodoWrite', 'WebSearch', 'WebFetch')

$script:CopilotShellTools = if ($env:OS -eq 'Windows_NT') { @('powershell', 'read_powershell', 'write_powershell', 'stop_powershell', 'list_powershell') }
else { @('bash', 'read_bash', 'write_bash', 'stop_bash', 'list_bash') }
# Claude Code tool -> the Copilot CLI tools that do the same job.
$script:CopilotToolMap = [ordered]@{
  Read = @('view'); Write = @('create'); Edit = @('edit', 'apply_patch'); Glob = @('glob'); Grep = @('grep'); Skill = @('skill')
  Bash = $script:CopilotShellTools; PowerShell = $script:CopilotShellTools; TodoWrite = @('sql')
  WebSearch = @('web_search'); WebFetch = @('web_fetch')
}
# Copilot CLI tool -> Claude Code tool name, so that "tool-input" checks read the same on both CLIs.
$script:ClaudeToolNames = @{
  view = 'Read'; create = 'Write'; edit = 'Edit'; apply_patch = 'Edit'; glob = 'Glob'; grep = 'Grep'; skill = 'Skill'
  powershell = 'PowerShell'; write_powershell = 'PowerShell'; bash = 'Bash'; write_bash = 'Bash'; sql = 'TodoWrite'
  web_search = 'WebSearch'; web_fetch = 'WebFetch'
}

function Get-CopilotTools {
  param([string[]]$AllowedTools)
  $missing = @($AllowedTools | Where-Object { -not $script:CopilotToolMap.Contains($_) })
  if ($missing.Count) { throw "No Copilot CLI tool for: $($missing -join ', '). Add it to `$script:CopilotToolMap in scripts\lib\Session.ps1." }
  @($AllowedTools | ForEach-Object { $script:CopilotToolMap[$_] } | Select-Object -Unique)
}

function Get-CliModel {
  <#
  .SYNOPSIS
    The model name for the CLI: a Copilot session gets the id that config.json "copilotModels" gives for an alias
    ("sonnet"); other names pass unchanged.
  #>
  param([string]$Cli, [string]$Model)
  if ($Cli -eq 'copilot' -and $script:Config.copilotModels -and $script:Config.copilotModels.$Model) { return [string]$script:Config.copilotModels.$Model }
  $Model
}

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
    Clis           = $(if ($cfg.cli) { @($cfg.cli) } else { $script:Clis })
    Requires       = @($cfg.requires | Where-Object { $_ })
    TimeoutMinutes = $(if ($cfg.timeoutMinutes) { [int]$cfg.timeoutMinutes } else { 20 })
    SeedCopy       = @($cfg.seedCopy | Where-Object { $_ })
    SeedRemove     = @($cfg.seedRemove | Where-Object { $_ })
    SeedCommands   = @($cfg.seedCommands | Where-Object { $_ })
    SeedDiffs      = @($cfg.seedDiffs | Where-Object { $_ })
    EmptySeed      = [bool]$cfg.emptySeed
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
  <#
  .SYNOPSIS
    Replaces {{today}}, {{date}}, {{workspace}} and {{include:<path in the repository>#<n>}} (the n-th fenced code
    block of that file, so a prompt can use a vacancy text or the user answers of materials/ without a copy).
  #>
  param([string]$Text, [string]$Workspace)
  $Text = [regex]::Replace($Text, '\{\{include:([^#}]+)#(\d+)\}\}', {
      param($m)
      $file = Join-Path $script:Repo $m.Groups[1].Value
      $content = (Get-Content $file -Raw) -replace "`r`n", "`n"
      $blocks = [regex]::Matches($content, '(?ms)^```[^\n]*\n(.*?)\n```')
      $n = [int]$m.Groups[2].Value
      if ($n -lt 1 -or $n -gt $blocks.Count) { throw "$($m.Value): $file has $($blocks.Count) code block(s)" }
      $blocks[$n - 1].Groups[1].Value
    })
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
    "to"); copy the fixture's seed\ folder over it; apply the "seedDiffs" (paths in the repository) and seed.diff
    with git apply; run "seedCommands" (pwsh commands in the workspace, for example a CV build; {{plugin}} is the
    plugin folder); commit everything.
  #>
  param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$Path)
  if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
  New-Item -ItemType Directory -Force $Path | Out-Null
  if (-not $Fixture.EmptySeed) { Copy-Item (Join-Path $script:SeedDir '*') $Path -Recurse -Force }
  if (-not $Fixture.EmptySeed) { Copy-Item (Join-Path $script:SeedDir '.gitignore') $Path -Force -ErrorAction SilentlyContinue }
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
  # An empty seed starts as a plain folder without git: the skill under test (init-workspace) makes the repository.
  if ($Fixture.EmptySeed) { return }
  $null = git -C $Path init -q -b main 2>&1
  # --ignore-whitespace: the diffs are stored with LF, the seed files may have CRLF (core.autocrlf).
  $diffs = @($Fixture.SeedDiffs | ForEach-Object { Join-Path $script:Repo $_ }) + @(Join-Path $Fixture.Dir 'seed.diff' | Where-Object { Test-Path $_ })
  foreach ($diff in $diffs) {
    $out = git -C $Path apply --ignore-whitespace --whitespace=nowarn $diff 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git apply $diff failed: $out" }
  }
  foreach ($cmd in $Fixture.SeedCommands) {
    $line = (Expand-Placeholders $cmd $Path).Replace('{{plugin}}', ($script:PluginDir -replace '\\', '/'))
    Push-Location $Path
    try {
      $out = & pwsh -NoProfile -Command $line 2>&1 | Out-String
      if ($LASTEXITCODE -ne 0) { throw "seedCommands failed: $line`n$out" }
    }
    finally { Pop-Location }
  }
  $null = git -C $Path add -A 2>&1
  $null = git -C $Path -c user.name=jobsearch-tests -c user.email=tests@example.com commit -q -m 'Seed workspace' 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git commit of the seed workspace failed in $Path" }
}

function Get-SessionArguments {
  <#
  .SYNOPSIS
    The command line of one test session turn. The prompt goes on stdin.
  .DESCRIPTION
    Claude Code: a turn after the first continues the session with --resume <ResumeId>.
    Copilot CLI: the first turn sets the session id with --session-id <NewSessionId>; a later turn continues it with
    --resume <ResumeId>.
  #>
  param([Parameter(Mandatory)]$Fixture, [string]$Cli = 'claude', [string]$Model, [string]$Effort, [string]$ResumeId, [string]$NewSessionId)
  if ($Cli -eq 'copilot') {
    $tools = Get-CopilotTools $Fixture.AllowedTools
    # A tool not in --available-tools is not shown to the model; --allow-tool approves the calls, so that the
    # session never waits for a prompt. A call that no rule approves is denied.
    $a = @('--output-format', 'json', '--model', (Get-CliModel $Cli $Model), '--no-auto-update', '--no-ask-user',
      '--disable-builtin-mcps', '--plugin-dir', $script:PluginDir, '--add-dir', $script:PluginDir,
      "--available-tools=$($tools -join ',')")
    if ($tools | Where-Object { $_ -in 'view', 'glob', 'grep' }) { $a += '--allow-tool=read' }
    if ($tools | Where-Object { $_ -in 'create', 'edit', 'apply_patch' }) { $a += '--allow-tool=write' }
    if ($tools | Where-Object { $_ -in $script:CopilotShellTools }) { $a += '--allow-tool=shell' }
    if ($tools | Where-Object { $_ -in 'web_fetch', 'web_search' }) { $a += '--allow-all-urls' }
    if ($Effort) { $a += @('--reasoning-effort', $Effort) }
    if ($ResumeId) { $a += @('--resume', $ResumeId) } elseif ($NewSessionId) { $a += @('--session-id', $NewSessionId) }
    return $a
  }
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

function Get-CliCommand {
  <#
  .SYNOPSIS
    The program and the leading arguments that start the CLI.
  .DESCRIPTION
    An npm shim (copilot.cmd) runs through cmd.exe, which changes quoted arguments; its node script is started
    directly instead.
  #>
  param([Parameter(Mandatory)][string]$Cli)
  $cmd = Get-Command $Cli -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { throw "'$Cli' is not on PATH. Install the CLI or run with -Cli $(@($script:Clis | Where-Object { $_ -ne $Cli })[0])." }
  if ($cmd.Source -match '\.(cmd|bat)$') {
    $dir = Split-Path $cmd.Source -Parent
    $loader = Join-Path $dir 'node_modules\@github\copilot\npm-loader.js'
    if (Test-Path $loader) {
      $node = Join-Path $dir 'node.exe'
      if (-not (Test-Path $node)) { $node = (Get-Command node -CommandType Application | Select-Object -First 1).Source }
      return @($node, $loader)
    }
  }
  @($cmd.Source)
}

function Invoke-Cli {
  <#
  .SYNOPSIS
    Runs the CLI with the prompt on stdin in a clean environment; returns exit code, stdout, stderr, seconds.
  .DESCRIPTION
    The variables of a hosting Claude Code or Copilot session (CLAUDECODE, CLAUDE_CODE_*, COPILOT_*, ...) are
    removed, so the test session behaves like one started from a terminal. A Copilot session gets COPILOT_HOME =
    $script:CopilotHome. COPILOT_GITHUB_TOKEN and the JOBSEARCH_* variables pass through.
  #>
  param([string]$Cli = 'claude', [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][string]$WorkingDirectory, [int]$TimeoutMinutes = 20)
  $command = @(Get-CliCommand $Cli)
  $psi = [Diagnostics.ProcessStartInfo]::new($command[0])
  foreach ($x in @($command | Select-Object -Skip 1) + $Arguments) { $psi.ArgumentList.Add($x) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $psi.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
  foreach ($k in @($psi.Environment.Keys)) {
    if ($k -match '^(CLAUDECODE|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID|CLAUDE_PREVIEW_|COPILOT_)' -and $k -ne 'COPILOT_GITHUB_TOKEN') { [void]$psi.Environment.Remove($k) }
  }
  if ($Cli -eq 'copilot') {
    New-Item -ItemType Directory -Force $script:CopilotHome | Out-Null
    $psi.Environment['COPILOT_HOME'] = $script:CopilotHome
    $psi.Environment['COPILOT_AUTO_UPDATE'] = 'false'
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

function ConvertFrom-CliOutput {
  <#
  .SYNOPSIS
    Reads the stdout of one turn: the answer, the session id, the error flag, the permission denials and the cost.
  .DESCRIPTION
    Claude Code prints one JSON object (--output-format json). Copilot CLI prints JSON lines (events): the answer is
    the text of the last assistant message without tool calls, a denial is a tool call that ends with the error code
    "denied", and the cost is the session's AI credits so far (CumulativeNanoAiu; 1 AI credit = 1e9 nano = 0.01 USD).
    Parsed is $false when the output has no result.
  #>
  param([string]$Cli = 'claude', [string]$Out)
  if ($Cli -eq 'copilot') {
    $events = @(foreach ($line in ($Out -split "`r?`n")) {
        if ($line.Trim().StartsWith('{')) { try { $line | ConvertFrom-Json -Depth 64 } catch { } }
      })
    $result = $events | Where-Object type -eq 'result' | Select-Object -Last 1
    $messages = @($events | Where-Object { $_.type -eq 'assistant.message' -and -not $_.data.parentToolCallId })
    $final = $messages | Where-Object { -not @($_.data.toolRequests).Count -and $_.data.content } | Select-Object -Last 1
    if (-not $final) { $final = $messages | Where-Object { $_.data.content } | Select-Object -Last 1 }
    $names = @{}
    foreach ($e in @($events | Where-Object type -eq 'tool.execution_start')) { $names[$e.data.toolCallId] = $e.data.toolName }
    $denied = @($events | Where-Object { $_.type -eq 'tool.execution_complete' -and $_.data.error.code -eq 'denied' } | ForEach-Object { $names[$_.data.toolCallId] })
    $errors = @($events | Where-Object type -eq 'session.error' | ForEach-Object { [string]$_.data.message })
    $nano = $events | Where-Object type -eq 'session.usage_checkpoint' | Select-Object -Last 1 | ForEach-Object { [double]$_.data.totalNanoAiu }
    return [pscustomobject]@{
      Parsed = [bool]$result; Answer = $(if ($final) { [string]$final.data.content } else { '' }); SessionId = $result.sessionId
      IsError = [bool]($result -and ($result.exitCode -ne 0 -or $errors.Count)); Error = ($errors -join ' ')
      CostUsd = $null; CumulativeNanoAiu = $nano
      Denials = $denied.Count; DeniedTools = @($denied | Where-Object { $_ } | Sort-Object -Unique)
    }
  }
  $j = try { $Out | ConvertFrom-Json } catch { $null }
  [pscustomobject]@{
    Parsed = [bool]$j; Answer = $(if ($j) { [string]$j.result } else { '' }); SessionId = $(if ($j) { $j.session_id })
    IsError = [bool]($j -and $j.is_error); Error = ''
    CostUsd = $(if ($j) { [double]$j.total_cost_usd } else { 0 }); CumulativeNanoAiu = $null
    Denials = $(if ($j -and $j.permission_denials) { @($j.permission_denials).Count } else { 0 })
    DeniedTools = $(if ($j -and $j.permission_denials) { @($j.permission_denials | ForEach-Object { $_.tool_name } | Sort-Object -Unique) } else { @() })
  }
}

function Find-Transcript {
  <#
  .SYNOPSIS
    The transcript of a session: ~/.claude/projects/*/<id>.jsonl, or events.jsonl in the Copilot session state.
  #>
  param([string]$Cli = 'claude', [Parameter(Mandatory)][string]$SessionId)
  if ($Cli -eq 'copilot') {
    $f = Join-Path $script:CopilotHome "session-state\$SessionId\events.jsonl"
    if (Test-Path $f) { return $f }
    return $null
  }
  Get-ChildItem (Join-Path $HOME '.claude\projects') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "$SessionId.jsonl" } | Where-Object { Test-Path $_ } | Select-Object -First 1
}
