# Judge, session metrics, run history and report of a test run. Dot-source Session.ps1 first.

$script:HistoryFile = Join-Path $script:TestsDir 'run-history.csv'
$script:ReportsDir = Join-Path $script:TestsDir 'reports'
$script:HistoryColumns = @('run_id', 'started', 'note', 'fixture', 'rep', 'model', 'effort', 'plugin_version', 'commit', 'status',
  'turns', 'checks_passed', 'checks_total', 'score', 'max_score', 'false_positives', 'permission_denials',
  'duration_s', 'calls', 'output_tokens', 'max_context', 'cost_usd', 'cost_units')

# The transcript parser of harness-kit (profile-session): context size, calls, output tokens, weighted cost.
. (Join-Path $script:Repo 'plugins\harness-kit\skills\profile-session\scripts\lib\Session-Profile.ps1')

function Invoke-Judge {
  <#
  .SYNOPSIS
    Scores one turn's material against a ground truth with a headless session; returns score, max, false positives.
  #>
  param([Parameter(Mandatory)][string]$GroundTruthFile, [Parameter(Mandatory)][string]$MaterialFile, [string]$Model = 'sonnet', [Parameter(Mandatory)][string]$ScratchDir)
  $gt = Get-Content $GroundTruthFile -Raw
  $max = if ($gt -match 'Max score:\s*(\d+)') { [int]$Matches[1] } else { throw "$GroundTruthFile has no 'Max score: N' line" }
  $prompt = (Get-Content (Join-Path $PSScriptRoot 'judge-prompt.md') -Raw).Replace('{{ground_truth}}', $gt).Replace('{{material}}', (Get-Content $MaterialFile -Raw))
  New-Item -ItemType Directory -Force $ScratchDir | Out-Null
  $userMd = (Join-Path $HOME '.claude\CLAUDE.md') -replace '\\', '/'
  $settings = @{ claudeMdExcludes = @($userMd) } | ConvertTo-Json -Compress
  $args_ = @('-p', '--output-format', 'json', '--model', $Model, '--setting-sources', 'project', '--settings', $settings,
    '--strict-mcp-config', '--tools', '', '--no-session-persistence')
  $r = Invoke-Claude -Arguments $args_ -Prompt $prompt -WorkingDirectory $ScratchDir -TimeoutMinutes 10
  $text = try { ($r.Out | ConvertFrom-Json).result } catch { $r.Out }
  $cost = try { [double]($r.Out | ConvertFrom-Json).total_cost_usd } catch { 0 }
  # The score is the sum of the items; if the judge corrects an item, its last line counts. The "Score:" line is the
  # fallback, because a judge sometimes corrects an item without changing the total.
  $items = @{}
  foreach ($m in [regex]::Matches($text, '(?m)^(?:Correction to )?Item (\d+):\s*([01])\b')) { $items[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  $score = if ($items.Count) { ($items.Values | Measure-Object -Sum).Sum }
  elseif ($text -match 'Score:\s*(\d+)\s*/\s*(\d+)') { [int]$Matches[1] } else { $null }
  $fp = if ($text -match 'False positives:\s*(\d+)') { [int]$Matches[1] } elseif ($text -match 'False positives:\s*none') { 0 } else { $null }
  [pscustomobject]@{ Score = $score; Max = $max; FalsePositives = $fp; Text = [string]$text; CostUsd = $cost }
}

function Get-SessionMetrics {
  param([string]$Transcript)
  if (-not $Transcript -or -not (Test-Path $Transcript)) { return $null }
  $p = Read-WorkSession -File (Get-Item $Transcript)
  $rows = @($p.Rows)
  $subRows = @($p.Subagents | ForEach-Object { $_.Rows })
  [pscustomobject]@{
    Calls        = $rows.Count + $subRows.Count
    OutputTokens = (($rows + $subRows) | Measure-Object Out -Sum).Sum
    MaxContext   = ($rows | Measure-Object Ctx -Maximum).Maximum
    CostUnits    = [math]::Round((($rows + $subRows) | Measure-Object Cost -Sum).Sum)
  }
}

function Complete-Result {
  <#
  .SYNOPSIS
    Judges the turns of one result that have a ground truth and no score yet, adds the metrics and the status.
  #>
  param([Parameter(Mandatory)][string]$ResultFile, [string]$JudgeModel = 'sonnet', [int]$MinScore = -1)
  $dir = Split-Path $ResultFile -Parent
  $res = Get-Content $ResultFile -Raw | ConvertFrom-Json
  if ($res.status -eq 'skipped') { return $res }
  foreach ($t in $res.turns) {
    if ($t.groundTruth -and $null -eq $t.judge) {
      $j = try {
        Invoke-Judge -GroundTruthFile $t.groundTruth -MaterialFile (Join-Path $dir "judge-input-$($t.n).md") -Model $JudgeModel -ScratchDir (Join-Path $script:TempRoot 'judge')
      }
      catch {
        [pscustomobject]@{ Score = $null; Max = 0; FalsePositives = $null; Text = "Judge error: $($_.Exception.Message)"; CostUsd = 0 }
      }
      Set-Content -LiteralPath (Join-Path $dir "judge-$($t.n).md") -Value $j.Text -Encoding UTF8
      $t | Add-Member -Force judge ([pscustomobject]@{ score = $j.Score; max = $j.Max; falsePositives = $j.FalsePositives; costUsd = $j.CostUsd })
    }
  }
  $m = Get-SessionMetrics (Join-Path $dir 'transcript.jsonl')
  $res | Add-Member -Force metrics $m
  $checks = @($res.turns | ForEach-Object { $_.checks } | Where-Object { $_ })
  $judged = @($res.turns | Where-Object { $_.judge })
  $score = if ($judged.Count) { ($judged | ForEach-Object { [int]$_.judge.score } | Measure-Object -Sum).Sum } else { $null }
  $max = if ($judged.Count) { ($judged | ForEach-Object { [int]$_.judge.max } | Measure-Object -Sum).Sum } else { $null }
  $need = if ($MinScore -ge 0) { $MinScore } else { $max }
  $failedChecks = @($checks | Where-Object { -not $_.Pass })
  $sessionError = @($res.turns | Where-Object { $_.exitCode -ne 0 -or $_.isError })
  $status = if ($sessionError.Count) { 'error' }
  elseif ($failedChecks.Count) { 'fail' }
  elseif ($judged.Count -and ($null -eq $score -or $score -lt $need)) { 'fail' }
  else { 'pass' }
  $res | Add-Member -Force status $status
  $res | Add-Member -Force score $score
  $res | Add-Member -Force maxScore $max
  $res | Add-Member -Force checksPassed (@($checks | Where-Object Pass).Count)
  $res | Add-Member -Force checksTotal $checks.Count
  $res | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
  $res
}

function ConvertTo-HistoryRow {
  param($Run, $Res)
  $fp = @($Res.turns | Where-Object { $_.judge } | ForEach-Object { $_.judge.falsePositives } | Where-Object { $null -ne $_ })
  [pscustomobject][ordered]@{
    run_id             = $Run.runId
    started            = $Run.started
    note               = $Run.note
    fixture            = $Res.fixture
    rep                = $Res.rep
    model              = $Run.model
    effort             = $(if ($Run.effort) { $Run.effort } else { 'default' })
    plugin_version     = $Run.pluginVersion
    commit             = $Run.commit
    status             = $Res.status
    turns              = @($Res.turns).Count
    checks_passed      = $Res.checksPassed
    checks_total       = $Res.checksTotal
    score              = $Res.score
    max_score          = $Res.maxScore
    false_positives    = $(if ($fp.Count) { ($fp | Measure-Object -Sum).Sum } else { $null })
    permission_denials = (@($Res.turns | ForEach-Object { [int]$_.permissionDenials }) | Measure-Object -Sum).Sum
    duration_s         = [math]::Round((@($Res.turns | ForEach-Object { [double]$_.seconds }) | Measure-Object -Sum).Sum)
    calls              = $Res.metrics.Calls
    output_tokens      = $Res.metrics.OutputTokens
    max_context        = $Res.metrics.MaxContext
    cost_usd           = ([math]::Round((@($Res.turns | ForEach-Object { [double]$_.costUsd }) | Measure-Object -Sum).Sum, 4)).ToString([Globalization.CultureInfo]::InvariantCulture)
    cost_units         = $Res.metrics.CostUnits
  }
}

function Update-History {
  <#
  .SYNOPSIS
    Writes the rows of one run into run-history.csv; rows of the same run id are replaced.
  #>
  param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$RunId)
  $old = if (Test-Path $script:HistoryFile) { @(Import-Csv $script:HistoryFile | Where-Object run_id -ne $RunId) } else { @() }
  @($old) + @($Rows) | Select-Object $script:HistoryColumns | Export-Csv $script:HistoryFile -NoTypeInformation -Encoding UTF8
}

# History values are written with a decimal point whatever the culture.
function ConvertTo-Double($v) { [double]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture) }

function Get-Mean([object[]]$Values) {
  $v = @($Values | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { ConvertTo-Double $_ })
  if (-not $v.Count) { return $null }
  ($v | Measure-Object -Average).Average
}

function Get-StdDev([object[]]$Values) {
  $v = @($Values | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { ConvertTo-Double $_ })
  if ($v.Count -lt 2) { return 0 }
  $m = ($v | Measure-Object -Average).Average
  [math]::Sqrt((($v | ForEach-Object { ($_ - $m) * ($_ - $m) }) | Measure-Object -Sum).Sum / ($v.Count - 1))
}

function Get-Verdict {
  <#
  .SYNOPSIS
    Compares a fixture's rows of this run with its rows of the previous run that ran it.
  .DESCRIPTION
    REGRESSION: a pass rate lower than before, or a mean score lower by more than the noise. Improvement: the
    opposite. Noise of the score: the larger of 1 point and two standard deviations of both runs' scores.
  #>
  param([object[]]$Now, [object[]]$Before)
  if (-not $Before.Count) { return 'first run' }
  $rate = { param($r) @($r | Where-Object status -eq 'pass').Count / [math]::Max(1, @($r).Count) }
  $rn = & $rate $Now; $rb = & $rate $Before
  $sn = Get-Mean ($Now | ForEach-Object score); $sb = Get-Mean ($Before | ForEach-Object score)
  $noise = [math]::Max(1, 2 * [math]::Max((Get-StdDev ($Now | ForEach-Object score)), (Get-StdDev ($Before | ForEach-Object score))))
  if ($rn -lt $rb) { return 'REGRESSION' }
  if ($null -ne $sn -and $null -ne $sb -and ($sb - $sn) -gt $noise) { return 'REGRESSION' }
  if ($rn -gt $rb) { return 'improvement' }
  if ($null -ne $sn -and $null -ne $sb -and ($sn - $sb) -gt $noise) { return 'improvement' }
  'within noise'
}

function Format-Num($v, [string]$fmt = '0.#') {
  if ($null -eq $v -or "$v" -eq '') { return '–' }
  ([double]$v).ToString($fmt, [Globalization.CultureInfo]::InvariantCulture)
}

function Write-Report {
  <#
  .SYNOPSIS
    Writes reports/<date>-<run id>.md: per fixture the result, the comparison with its previous run, and the
    failed checks with expected and actual values.
  #>
  param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][object[]]$Results)
  New-Item -ItemType Directory -Force $script:ReportsDir | Out-Null
  $history = if (Test-Path $script:HistoryFile) { @(Import-Csv $script:HistoryFile) } else { @() }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# jobsearch-kit test run $($Run.runId)")
  $lines.Add('')
  $lines.Add("- Note: $($Run.note)")
  $lines.Add("- Started: $($Run.started); model $($Run.model), effort $(if ($Run.effort) { $Run.effort } else { 'default' }), judge $($Run.judgeModel)")
  $lines.Add("- Plugin version $($Run.pluginVersion), commit $($Run.commit)")
  $all = @($history | Where-Object run_id -eq $Run.runId)
  $lines.Add("- Sessions: $($all.Count); time $(Format-Num ((@($all | ForEach-Object { ConvertTo-Double $_.duration_s }) | Measure-Object -Sum).Sum / 60) '0.0') min; cost `$$(Format-Num ((@($all | ForEach-Object { ConvertTo-Double $_.cost_usd }) | Measure-Object -Sum).Sum) '0.00') (API price; on a plan it uses the usage limit)")
  $lines.Add('')
  $lines.Add('| Fixture | Passed | Checks | Score | False pos. | Denials | Time, s | Cost, $ | Before: passed, score | Verdict |')
  $lines.Add('|---|---|---|---|---|---|---|---|---|---|')
  foreach ($g in ($all | Group-Object fixture)) {
    $now = @($g.Group)
    $prevId = $history | Where-Object { $_.fixture -eq $g.Name -and $_.run_id -ne $Run.runId -and $_.run_id -lt $Run.runId -and $_.status -ne 'skipped' } |
      Sort-Object run_id | Select-Object -Last 1 -ExpandProperty run_id
    $before = @($history | Where-Object { $_.fixture -eq $g.Name -and $_.run_id -eq $prevId })
    $skipped = @($now | Where-Object status -eq 'skipped').Count -eq $now.Count
    $verdict = if ($skipped) { 'skipped' } else { Get-Verdict $now $before }
    $passed = "$(@($now | Where-Object status -eq 'pass').Count)/$($now.Count)"
    $checks = "$((@($now | ForEach-Object { [int]$_.checks_passed }) | Measure-Object -Sum).Sum)/$((@($now | ForEach-Object { [int]$_.checks_total }) | Measure-Object -Sum).Sum)"
    $score = if ($now[0].max_score) { "$(Format-Num (Get-Mean ($now | ForEach-Object score)))/$($now[0].max_score)" } else { '–' }
    $prev = if ($before.Count) { "$(@($before | Where-Object status -eq 'pass').Count)/$($before.Count), $(Format-Num (Get-Mean ($before | ForEach-Object score)))" } else { '–' }
    $lines.Add("| $($g.Name) | $passed | $checks | $score | $(Format-Num (Get-Mean ($now | ForEach-Object false_positives))) | $((@($now | ForEach-Object { [int]$_.permission_denials }) | Measure-Object -Sum).Sum) | $(Format-Num (Get-Mean ($now | ForEach-Object duration_s)) '0') | $(Format-Num (Get-Mean ($now | ForEach-Object cost_usd)) '0.00') | $prev | $verdict |")
  }
  $problems = @($Results | Where-Object { $_.status -ne 'pass' })
  if ($problems.Count) {
    $lines.Add('')
    $lines.Add('## Problems')
    foreach ($r in $problems) {
      $lines.Add('')
      $lines.Add("### $($r.fixture), repetition $($r.rep): $($r.status)")
      if ($r.skipReason) { $lines.Add(''); $lines.Add("Skipped: $($r.skipReason)"); continue }
      # The report is a tracked file: no path of this machine in it.
      if ($r.workspaceKept) { $lines.Add(''); $lines.Add("Workspace kept for inspection: ``$($r.workspace.Replace($script:TempRoot, '%TEMP%\jobsearch-tests'))``") }
      foreach ($t in $r.turns) {
        if ($t.exitCode -ne 0 -or $t.isError) { $lines.Add(''); $lines.Add("- Turn $($t.n): the session failed (exit code $($t.exitCode)): $($t.error)") }
        foreach ($c in @($t.checks | Where-Object { -not $_.Pass })) {
          $lines.Add("- Turn $($t.n), check ``$($c.Name)``: expected $($c.Expected); actual: $(($c.Actual -replace '\s+', ' ').Trim())")
        }
        if ($t.judge -and ($null -eq $t.judge.score -or $t.judge.score -lt $t.judge.max)) {
          $lines.Add("- Turn $($t.n), judge: $($t.judge.score)/$($t.judge.max), false positives $($t.judge.falsePositives) (see judge-$($t.n).md in the run folder)")
        }
      }
    }
  }
  $file = Join-Path $script:ReportsDir "$($Run.runId).md"
  $lines | Set-Content -LiteralPath $file -Encoding UTF8
  $file
}
