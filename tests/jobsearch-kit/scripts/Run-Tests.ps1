<#
.SYNOPSIS
  Runs jobsearch-kit skill fixtures in fresh headless sessions (Claude Code or GitHub Copilot CLI) and checks the
  results.

.DESCRIPTION
    pwsh -File tests\jobsearch-kit\scripts\Run-Tests.ps1 -Fixture <names or masks> -Note "<what changed>"
         [-Cli claude|copilot] [-DryRun] [-Model sonnet] [-Effort <level>] [-JudgeModel sonnet] [-JudgeCli claude|copilot]
         [-Repetitions <n>] [-Keep] [-IncludeSlow]

  For every fixture repetition: a new workspace under %TEMP%\jobsearch-tests\<run id>\ (the seed workspace of
  config.json, the fixture's seed files, git init and one commit); one claude -p (or copilot) session per turn, the
  next turns with --resume; the checks of each turn; the judge for each turn with a ground truth. Then
  Collect-Tests.ps1 adds the rows to run-history.csv and writes reports\<run id>.md.

  The sessions use the Claude usage limit (or API cost), or the Copilot AI credits. The plan printed at the start
  says how many sessions run and the expected time from earlier runs.

  -Cli           the CLI of the test sessions: claude (default) or copilot.
  -JudgeCli      the CLI of the judge; default claude, so that the scores of both CLIs come from the same judge.
  -Model         a model name; for copilot, config.json "copilotModels" maps an alias (sonnet) to a Copilot model id.
  -Fixture       fixture folder names or -like masks; default all fixtures except the slow ones.
  -IncludeSlow   also run fixtures with "slow": true when a mask selects them (a slow fixture named exactly always runs).
  -Repetitions   overrides "repetitions" of fixture.json.
  -Keep          keeps every workspace; by default only workspaces with a failed check or session are kept.
  -DryRun        prints the plan and the session command line; runs nothing.
#>
param(
  [string[]]$Fixture = @('*'),
  [string]$Note = '',
  [ValidateSet('claude', 'copilot')][string]$Cli = 'claude',
  [switch]$DryRun,
  [string]$Model = 'sonnet',
  [string]$Effort = '',
  [string]$JudgeModel = 'sonnet',
  [ValidateSet('claude', 'copilot')][string]$JudgeCli = 'claude',
  [int]$Repetitions = 0,
  [switch]$Keep,
  [switch]$IncludeSlow
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Session.ps1')
. (Join-Path $PSScriptRoot 'lib\Checks.ps1')
. (Join-Path $PSScriptRoot 'lib\Collect.ps1')

if (-not $DryRun -and -not $Note) { throw 'Give -Note "<what changed>": it goes into the run history and the report.' }

# pwsh -File passes "a,b" as one string.
$Fixture = @($Fixture | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$fixturesDir = Join-Path $script:TestsDir 'fixtures'
$all = Get-ChildItem $fixturesDir -Directory | ForEach-Object { Read-Fixture $_.FullName }
$matched = @($all | Where-Object {
    $f = $_
    $byMask = @($Fixture | Where-Object { $f.Name -like $_ }).Count -gt 0
    $exact = $Fixture -contains $f.Name
    $byMask -and (-not $f.Slow -or $exact -or $IncludeSlow)
  })
# A fixture with "cli" in fixture.json runs only in the sessions of those CLIs.
$otherCli = @($matched | Where-Object { $_.Clis -notcontains $Cli })
$selected = @($matched | Where-Object { $_.Clis -contains $Cli })
if (-not $selected.Count) { throw "No fixture for $Cli matches: $($Fixture -join ', '). Fixtures: $(($all.Name) -join ', ')" }
foreach ($f in $selected) { if ($Cli -eq 'copilot') { $null = Get-CopilotTools $f.AllowedTools } }
$null = Get-CliCommand $Cli
if ($JudgeCli -ne $Cli -and @($selected | Where-Object { $_.Turns | Where-Object GroundTruth }).Count) { $null = Get-CliCommand $JudgeCli }

# The plan, with the expected time from the history of the same CLI.
$history = @(Read-History | Where-Object cli -eq $Cli)
$sessions = 0; $expected = 0
Write-Output "Plan ($Cli):"
foreach ($f in $selected) {
  $reps = if ($Repetitions -gt 0) { $Repetitions } else { $f.Repetitions }
  $past = @($history | Where-Object { $_.fixture -eq $f.Name -and $_.status -ne 'skipped' } | ForEach-Object { [double]::Parse($_.duration_s, [Globalization.CultureInfo]::InvariantCulture) })
  $each = if ($past.Count) { ($past | Measure-Object -Average).Average } else { 120 * $f.Turns.Count }
  $sessions += $reps * $f.Turns.Count; $expected += $reps * $each
  Write-Output ("  {0}: {1} repetition(s) x {2} turn(s), about {3:0.#} min{4}" -f $f.Name, $reps, $f.Turns.Count, ($reps * $each / 60), $(if ($f.Slow) { ' (slow)' }))
}
if ($otherCli.Count) { Write-Output "  Left out, not for ${Cli} (fixture.json `"cli`"): $($otherCli.Name -join ', ')" }
$limit = if ($Cli -eq 'copilot') { 'the Copilot AI credits' } else { 'the Claude usage limit' }
Write-Output ("{0} session turn(s), about {1:0} min plus the judge. The sessions use {2}. Model {3}, judge {4} ({5})." -f $sessions, ($expected / 60), $limit, (Get-CliModel $Cli $Model), (Get-CliModel $JudgeCli $JudgeModel), $JudgeCli)

if ($DryRun) {
  $f = $selected[0]
  Write-Output ''
  Write-Output "Session command line of $($f.Name), turn 01 (prompt on stdin):"
  $line = (Get-SessionArguments -Fixture $f -Cli $Cli -Model $Model -Effort $Effort -NewSessionId '<new session id>') | ForEach-Object { if ($_ -match '[\s"{<]') { "'$_'" } else { $_ } }
  Write-Output ("  $Cli " + ($line -join ' '))
  exit 0
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $script:TestsDir "runs\$runId"
New-Item -ItemType Directory -Force $runDir | Out-Null
# A Copilot home of this run only: no installed plugin, MCP server or user instruction of the developer.
$script:CopilotHome = Join-Path $script:TempRoot "$runId\copilot-home"
$run = [pscustomobject]@{
  runId = $runId; started = (Get-Date -Format 's'); note = $Note; cli = $Cli; model = $Model; effort = $Effort; judgeModel = $JudgeModel; judgeCli = $JudgeCli
  pluginVersion = (Get-PluginVersion); commit = ((git -C $script:Repo rev-parse --short HEAD) + $(if (git -C $script:Repo status --porcelain) { '+dirty' }))
  fixtures = @($selected.Name)
}
$run | ConvertTo-Json | Set-Content (Join-Path $runDir 'run.json') -Encoding UTF8

$limitHit = $false
foreach ($f in $selected) {
  if ($limitHit) { break }
  $reps = if ($Repetitions -gt 0) { $Repetitions } else { $f.Repetitions }
  for ($rep = 1; $rep -le $reps -and -not $limitHit; $rep++) {
    $outDir = Join-Path $runDir "$($f.Name)\r$rep"
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $resultFile = Join-Path $outDir 'result.json'
    $ws = Join-Path $script:TempRoot "$runId\$($f.Name)-r$rep"
    $res = [ordered]@{ fixture = $f.Name; rep = $rep; cli = $Cli; workspace = $ws; workspaceKept = $false; status = 'running'; skipReason = $null; sessionId = $null; turns = @() }

    $reasons = @($f.Requires | ForEach-Object { Test-Requirement $_ } | Where-Object { $_ })
    if ($reasons.Count) {
      $res.status = 'skipped'; $res.skipReason = $reasons -join '; '
      Write-Output "SKIP  $($f.Name) r${rep}: $($res.skipReason)"
      [pscustomobject]$res | ConvertTo-Json -Depth 8 | Set-Content $resultFile -Encoding UTF8
      continue
    }

    New-TestWorkspace -Fixture $f -Path $ws
    $scratch = Join-Path $script:TempRoot "$runId\scratch-$($f.Name)-r$rep"
    New-Item -ItemType Directory -Force $scratch | Out-Null
    $sessionId = $null
    $nanoAiu = 0
    foreach ($t in $f.Turns) {
      Write-Output "      $($f.Name) r$rep turn $($t.N) ..."
      $prompt = Expand-Placeholders (Get-Content $t.PromptFile -Raw) $ws
      $sessionArgs = Get-SessionArguments -Fixture $f -Cli $Cli -Model $Model -Effort $Effort -ResumeId $sessionId -NewSessionId ([guid]::NewGuid().ToString())
      $r = Invoke-Cli -Cli $Cli -Arguments $sessionArgs -Prompt $prompt -WorkingDirectory $ws -TimeoutMinutes $f.TimeoutMinutes
      $o = ConvertFrom-CliOutput -Cli $Cli -Out $r.Out
      $answer = $o.Answer
      if ($o.SessionId) { $sessionId = $o.SessionId }
      # Copilot reports the AI credits of the whole session so far: the cost of the turn is the difference.
      $cost = if ($null -ne $o.CumulativeNanoAiu) { ($o.CumulativeNanoAiu - $nanoAiu) / 1e11 } else { [double]$o.CostUsd }
      if ($null -ne $o.CumulativeNanoAiu) { $nanoAiu = $o.CumulativeNanoAiu }
      Set-Content -LiteralPath (Join-Path $outDir "answer-$($t.N).md") -Value $answer -Encoding UTF8
      if ($Cli -eq 'copilot') { Set-Content -LiteralPath (Join-Path $outDir "output-$($t.N).jsonl") -Value $r.Out -Encoding UTF8 }
      $turn = [ordered]@{
        n = $t.N; exitCode = $r.ExitCode; isError = [bool]($o.IsError -or -not $o.Parsed); seconds = [math]::Round($r.Seconds)
        costUsd = [math]::Round($cost, 4)
        permissionDenials = $o.Denials
        deniedTools = @($o.DeniedTools)
        error = $(if ($r.ExitCode -ne 0 -or -not $o.Parsed -or $o.IsError) { (($o.Error + ' ' + $r.Err + ' ' + $(if (-not $o.Parsed) { $r.Out })) -replace '\s+', ' ').Trim() })
        checks = @(); groundTruth = $t.GroundTruth; judge = $null
      }
      $turn.checks = @(Invoke-TurnChecks -Turn $t -Workspace $ws -Answer $answer -FixtureDir $f.Dir -ScratchDir $scratch -Cli $Cli -Transcript $(if ($sessionId) { Find-Transcript -Cli $Cli -SessionId $sessionId }))
      foreach ($c in $turn.checks) {
        $mark = if ($c.Skipped) { 'skip' } elseif ($c.Pass) { 'ok  ' } else { 'FAIL' }
        Write-Output "      $mark  $($c.Name)$(if (-not $c.Pass) { " — expected $($c.Expected); actual: $(($c.Actual -replace '\s+', ' ').Trim())" })"
      }
      if ($t.GroundTruth) {
        $material = New-Object System.Collections.Generic.List[string]
        $material.Add("## The session's answer to the user (turn $($t.N))"); $material.Add(''); $material.Add($answer)
        foreach ($glob in $f.JudgeFiles) {
          foreach ($file in @(Get-WorkspaceFiles $ws $glob)) {
            $material.Add(''); $material.Add("## File: $(Get-RelativePath $ws $file.FullName)"); $material.Add('')
            $material.Add((Get-Content $file.FullName -Raw))
          }
        }
        $material | Set-Content -LiteralPath (Join-Path $outDir "judge-input-$($t.N).md") -Encoding UTF8
      }
      $res.turns += [pscustomobject]$turn
      if ($turn.exitCode -ne 0 -or $turn.isError -or -not $sessionId) {
        Write-Output "      FAIL  session of turn $($t.N): $($turn.error)"
        if ("$($turn.error) $answer" -match 'usage_limit_reached|hit your (session|usage|weekly) limit|exceeded your .{0,40}(allowance|budget|quota|limit)|no (premium requests|AI credits) left') { $limitHit = $true }
        break
      }
    }
    $res.sessionId = $sessionId
    if ($sessionId) {
      $tr = Find-Transcript -Cli $Cli -SessionId $sessionId
      if ($tr) { Copy-Item $tr (Join-Path $outDir 'transcript.jsonl') }
    }
    [pscustomobject]$res | ConvertTo-Json -Depth 8 | Set-Content $resultFile -Encoding UTF8
    $done = Complete-Result -ResultFile $resultFile -JudgeModel $JudgeModel -JudgeCli $JudgeCli -MinScore $(if ($null -ne $f.MinScore) { [int]$f.MinScore } else { -1 })
    $keepIt = $Keep -or $done.status -ne 'pass'
    if ($keepIt) { $done.workspaceKept = $true } else { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    $done | ConvertTo-Json -Depth 8 | Set-Content $resultFile -Encoding UTF8
    $judgeText = @($done.turns | Where-Object { $_.judge } | ForEach-Object { "turn $($_.n) judge $($_.judge.score)/$($_.judge.max), false positives $($_.judge.falsePositives)" }) -join '; '
    Write-Output ("{0}  {1} r{2}: checks {3}/{4}{5}{6}" -f $(if ($done.status -eq 'pass') { 'PASS' } else { $done.status.ToUpper() }), $f.Name, $rep,
      $done.checksPassed, $done.checksTotal, $(if ($judgeText) { "; $judgeText" }), $(if ($keepIt) { "; workspace kept: $ws" }))
  }
}

& (Join-Path $PSScriptRoot 'Collect-Tests.ps1') -Run $runDir -JudgeModel $JudgeModel -JudgeCli $JudgeCli
# The transcripts are in the run folder now; the Copilot home of the run is not needed any more.
Remove-Item $script:CopilotHome -Recurse -Force -ErrorAction SilentlyContinue
$runTemp = Join-Path $script:TempRoot $runId
if ((Test-Path $runTemp) -and -not (Get-ChildItem $runTemp -Force)) { Remove-Item $runTemp -Force }
if ($limitHit) {
  Write-Output "STOPPED: $limit is reached. Remove this run from the history, wait for the reset and run again."
  exit 2
}
