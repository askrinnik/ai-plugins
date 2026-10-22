<#
.SYNOPSIS
  Profiles one finished Claude Code session of the current repository and, with -Save, records it as one JSON file.
.DESCRIPTION
  Without -Save the profile is shown on screen and nothing tracked is written. With -Save the summary of the session
  is written to <resultsDir>/records/<yyyy-MM-dd>_<session id>.json (the UTC start date), and the HTML
  report is rebuilt from every record. A session that already has a record is rejected. One file per session means
  that saves on parallel branches never touch the same file.

  The session defaults to the one the skill runs in (-CurrentSession, then the CLAUDE_CODE_SESSION_ID environment
  variable). Without either, it is the newest interactive transcript; sessions listed in a manifest of
  excludeSessionManifests and SDK sessions are skipped there.

  Paths, patterns and cost weights come from settings files, merged in this order: profile-session.config.default.json
  in the skill folder, profile-session.config.json in the Claude config folder, profile-session.config.json in the
  repository root. See CONFIGURATION.md in the skill folder.

  The weekly plan limit is read from the results of the get_usage tool calls on the main thread of the transcript:
  the first one is the start, the last one the end. Call get_usage at the start of the session and again just
  before profiling it.
.PARAMETER Session          Session id or a unique prefix of it (8 characters are enough). The word `save` here acts as -Save.
.PARAMETER CurrentSession   Id of the session the skill runs in (the skill passes ${CLAUDE_SESSION_ID}). Used when no -Session is given; without it the CLAUDE_CODE_SESSION_ID environment variable is tried, then the newest interactive transcript.
.PARAMETER Save             Write the record of the session and rebuild the report.
.PARAMETER WorkItem         Work item id; defaults to the id found by workItemPattern in the branch of the session, in the first argument of the slash command named by workItemCommandPattern, or in the subject of a `git commit -m` command of the session. When the newest session is profiled and its transcript names no branch, the checked-out branch and the subject of its last commit are used.
.PARAMETER Lane             Bug or Feature; defaults to the prefix (bug-) of the work item's plan file found by lanePlanGlob; empty without one.
.PARAMETER Note             Free text stored with the record.
.PARAMETER NoCommit         Leave the commit of the record empty: for a record that is then amended into the current commit, whose id the amend changes, so no id stored in the record can name it.
.PARAMETER Marker          Label stored with the record (for example the rule change the session was the first to run under).
.PARAMETER Report           Rebuild report.html from the records without profiling anything.
.PARAMETER NoOpen           Do not open the report in the default browser after building it.
.PARAMETER Recompute        Recompute the measured figures of every record whose transcript is still here, over the calls the record first covered, and rebuild the report. The work item, lane, branch, commit, author, profile time, note, marker, change size and limit readings of a record are kept; a record without a transcript is left untouched, and a record whose figures did not change stays byte-identical.
.PARAMETER TopTurns         Number of costliest human turns shown on screen.
.PARAMETER TranscriptDir    Folder with the session transcripts (default: <Claude config dir>/projects/<repository key>).
.PARAMETER ResultsDir       Folder of records/ and report.html (default: .ai/benchmarks/sessions).
.PARAMETER DefaultsFile      Settings file with the default values (default: profile-session.config.default.json in the skill folder).
.PARAMETER UserConfig        Settings file of the user (default: profile-session.config.json in the Claude config folder).
.PARAMETER RepoConfig        Settings file of the repository (default: profile-session.config.json in the repository root).
.EXAMPLE
  pwsh <skill folder>/scripts/Profile-Session.ps1
.EXAMPLE
  pwsh <skill folder>/scripts/Profile-Session.ps1 6d1025ce -Save -WorkItem 662
.EXAMPLE
  pwsh <skill folder>/scripts/Profile-Session.ps1 -Report
#>
param(
  [Parameter(Position = 0)][string]$Session,
  [string]$CurrentSession,
  [switch]$Save,
  [string]$WorkItem,
  [string]$Lane,
  [string]$Note,
  [string]$Marker,
  [switch]$NoCommit,
  [switch]$Report,
  [switch]$NoOpen,
  [switch]$Recompute,
  [int]$TopTurns = 8,
  [string]$TranscriptDir,
  [string]$ResultsDir,
  [string]$DefaultsFile,
  [string]$UserConfig,
  [string]$RepoConfig
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'lib/Session-Profile.ps1')
. (Join-Path $PSScriptRoot 'lib/Session-Report.ps1')

$profilerVersion = 'profile-session/7'

$inv = [Globalization.CultureInfo]::InvariantCulture
if ($Session -eq 'save') { $Save = $true; $Session = '' }

$top = [string]((& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $top) { throw "Run the profiler from inside a git repository: the working directory $((Get-Location).Path) is not in one, or git is not on the path." }
$repoRoot = [IO.Path]::GetFullPath($top.Trim())
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if (-not $DefaultsFile) { $DefaultsFile = Join-Path $PSScriptRoot '../profile-session.config.default.json' }
if (-not $UserConfig) { $UserConfig = Join-Path $claudeDir 'profile-session.config.json' }
if (-not $RepoConfig) { $RepoConfig = Join-Path $repoRoot 'profile-session.config.json' }
$settings = Get-ProfileSettings $DefaultsFile $UserConfig $RepoConfig
$defaultWeights = Copy-CostWeights $script:costWeights
if (-not $ResultsDir) { $ResultsDir = if ([IO.Path]::IsPathRooted($settings.ResultsDir)) { $settings.ResultsDir } else { Join-Path $repoRoot $settings.ResultsDir } }
if (-not $TranscriptDir) {
  $TranscriptDir = Join-Path (Join-Path $claudeDir 'projects') ($repoRoot -replace '[^A-Za-z0-9]', '-')
}
$sessionOptions = @{ WorkItemPatterns = $settings.WorkItemPatterns; WorkItemCommandPattern = $settings.WorkItemCommandPattern; ActivityRules = $settings.ActivityRules }
$recordsDir = Join-Path $ResultsDir 'records'
$reportFile = Join-Path $ResultsDir 'report.html'

<#
.SYNOPSIS
  Ids of the sessions listed in the manifests of excludeSessionManifests, which are not work sessions (for example
  the test sessions of a benchmark harness).
#>
function Get-ExcludedSessionIds {
  $ids = @{}
  foreach ($dir in $settings.ExcludeSessionManifests) {
    $runs = if ([IO.Path]::IsPathRooted($dir)) { $dir } else { Join-Path $repoRoot $dir }
    if (-not (Test-Path $runs)) { continue }
    foreach ($m in Get-ChildItem $runs -Filter *_manifest.json) { foreach ($s in @((Get-Content $m.FullName -Raw | ConvertFrom-Json).sessions)) { if ($s.session) { $ids[[string]$s.session] = 1 } } }
  }
  $ids
}

<#
.SYNOPSIS
  Entry point recorded in the first lines of a transcript (for example claude-desktop, cli, sdk-cli).
#>
function Get-Entrypoint([IO.FileInfo]$File) {
  $n = 0
  foreach ($l in [IO.File]::ReadLines($File.FullName)) {
    if ($l -match '"entrypoint":"([^"]+)"') { return $Matches[1] }
    if (++$n -ge 200) { break }
  }
  ''
}

<#
.SYNOPSIS
  Resolves -Session to one transcript file: a unique id prefix; when empty the session the skill runs in (-CurrentSession,
  then CLAUDE_CODE_SESSION_ID), else the newest interactive session.
#>
function Resolve-SessionFile {
  if (-not (Test-Path $TranscriptDir)) { throw "No transcript folder at $TranscriptDir" }
  if ($Session) {
    $m = @(Get-ChildItem $TranscriptDir -File -Filter "$Session*.jsonl")
    if ($m.Count -eq 0) { throw "No session transcript starting with '$Session' in $TranscriptDir" }
    if ($m.Count -gt 1) { throw "'$Session' matches $($m.Count) sessions; give more characters of the id." }
    return $m[0]
  }
  # the session the skill runs in: the id the host substituted, else the one in the environment of the shell; a text
  # left unsubstituted ("${...}") or an id without a transcript here is no id
  foreach ($candidate in $CurrentSession, $env:CLAUDE_CODE_SESSION_ID) {
    if (-not $candidate -or $candidate -match '^\$\{') { continue }
    $own = Join-Path $TranscriptDir "$candidate.jsonl"
    if (Test-Path $own) { return (Get-Item $own) }
    Write-Warning "Session $candidate has no transcript in $TranscriptDir; taking the newest interactive session."
  }
  $harness = Get-ExcludedSessionIds
  foreach ($f in (Get-ChildItem $TranscriptDir -File -Filter *.jsonl | Sort-Object LastWriteTimeUtc -Descending)) {
    if ($harness.ContainsKey($f.BaseName)) { continue }
    if ((Get-Entrypoint $f) -like 'sdk*') { continue }
    return $f
  }
  throw "No interactive session transcript in $TranscriptDir"
}

<#
.SYNOPSIS
  Rounds a number half away from zero and formats it with invariant culture and the given number of decimals.
.DESCRIPTION
  The value is rounded first because a custom format such as '0' formats only 15 significant digits, which turns
  24838487.49999997 into 24838488.
#>
function Format-Num($x, [int]$Decimals = 0) { [Math]::Round([double]$x, $Decimals, [MidpointRounding]::AwayFromZero).ToString("F$Decimals", $inv) }

<#
.SYNOPSIS
  A number for a record: $null for an empty value, a whole number as Int64 so that it is written without a decimal
  point, otherwise a double rounded to the given number of decimals.
#>
function ConvertTo-RecordNumber($x, [int]$Decimals = 0) {
  if ($null -eq $x -or [string]$x -eq '') { return $null }
  # a number is not passed through text, which keeps only 15 significant digits and turns 24838487.49999997 into 24838487.5
  $v = if ($x -is [string]) { [double]::Parse($x, $inv) } else { [double]$x }
  $d = [Math]::Round($v, $Decimals, [MidpointRounding]::AwayFromZero)
  if ($d -eq [Math]::Truncate($d)) { [int64]$d } else { $d }
}

<#
.SYNOPSIS
  A text for a record: $null for an empty value.
#>
function ConvertTo-RecordText($x) { if ([string]::IsNullOrEmpty([string]$x)) { $null } else { [string]$x } }

<#
.SYNOPSIS
  Profiles a parsed session: the flat summary shown on screen, the limit figures and the record written by -Save.
#>
function New-SessionProfile($s, [string]$current) {
  $rows = $s.Rows; $subs = $s.Subagents
  if (-not $rows.Count) { throw "Session $($s.Id) has no model calls." }
  $mIn = ($rows | Measure-Object In -Sum).Sum; $mOut = ($rows | Measure-Object Out -Sum).Sum
  $mCR = ($rows | Measure-Object CR -Sum).Sum; $mCW = ($rows | Measure-Object CW -Sum).Sum
  $sIn = [int64](($subs | Measure-Object In -Sum).Sum); $sOut = [int64](($subs | Measure-Object Out -Sum).Sum)
  $sCR = [int64](($subs | Measure-Object CR -Sum).Sum); $sCW = [int64](($subs | Measure-Object CW -Sum).Sum)
  $in = $mIn + $sIn; $out = $mOut + $sOut; $cr = $mCR + $sCR; $cw = $mCW + $sCW
  # summed per call and per subagent, as the cost by activity and by subagent is, so the parts add up to the total
  $mainCost = ($rows | Measure-Object Cost -Sum).Sum
  $cost = $mainCost + [double](($subs | Measure-Object Cost -Sum).Sum)
  $reb = @($rows | Where-Object Rebuild)

  $wi = $WorkItem -replace '^#', ''
  $patterns = $settings.WorkItemPatterns
  if (-not $wi) { $wi = Find-WorkItem $s.Branch $patterns }
  if (-not $wi -and $s.CommandWorkItem) { $wi = $s.CommandWorkItem }
  if (-not $wi -and $s.CommitWorkItem) { $wi = $s.CommitWorkItem }
  $branch = $s.Branch
  # Claude Code records a branch whose name starts with "#" as HEAD, so on a work-item branch the transcript names no
  # branch; for the session being profiled right now the checked-out branch, or the work item in the subject of its
  # last commit, is that session's
  if (-not $branch -and $current) {
    $branch = $current
    if (-not $wi) { $wi = Find-WorkItem $current $patterns }
    if (-not $wi) { $wi = Find-WorkItem ([string]((& git -C $repoRoot log -1 --format=%s) | Select-Object -First 1)) $patterns }
  }
  # the local branch of the work item, when the transcript did not name one that exists
  if ($wi) {
    $exists = { param($b) & git -C $repoRoot rev-parse --verify --quiet "refs/heads/$b" *> $null; $LASTEXITCODE -eq 0 }
    if (-not ($branch -and (& $exists $branch))) {
      $own = @(& git -C $repoRoot for-each-ref --format='%(refname:short)' refs/heads | Where-Object { (Find-WorkItem $_ $patterns) -eq $wi })
      if ($own.Count) { $branch = [string]$own[0] }
    }
  }
  $commit = ''
  if ($branch -and -not $NoCommit) { $c =(& git -C $repoRoot rev-parse --verify --quiet --short=8 "refs/heads/$branch" 2>$null | Select-Object -First 1); if ($LASTEXITCODE -eq 0) { $commit = [string]$c } }
  $lane = $Lane
  if (-not $lane -and $wi) {
    $plan = if ($settings.LanePlanGlob) { Get-ChildItem (Join-Path $repoRoot ($settings.LanePlanGlob.Replace('{id}', $wi))) -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($plan) { $lane = if ($plan.Name -like 'bug-*') { 'Bug' } else { 'Feature' } }
  }
  $diff = Get-DiffSize $repoRoot $branch (Resolve-BaseBranch $repoRoot $settings.BaseBranch)

  $byAct = @($rows | Group-Object Cat | ForEach-Object { [pscustomobject]@{ Cat = $_.Name; Calls = $_.Count; Cost = ($_.Group | Measure-Object Cost -Sum).Sum } } | Sort-Object Cost, Cat -Descending)
  $bySub = Get-SubagentsByModel $subs
  $top = @($s.Carriers | Sort-Object Carry -Descending | Select-Object -First 3)
  $ruleSum = [ordered]@{}; foreach ($r in ($s.Rules | Sort-Object Name)) { $ruleSum[$r.Name] += $r.Tok }
  $timedCalls = @($rows | Select-Object Time, Cost) + @($subs | ForEach-Object { $_.CallCosts })
  $limit = Get-LimitUsage $s.UsageReadings $timedCalls
  $p40 = Get-PrefixMetrics $rows 40; $p70 = Get-PrefixMetrics $rows 70
  $w = $script:costWeights

  $profiled = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm', $inv)
  $author = [string]((& git -C $repoRoot config user.name) | Select-Object -First 1)
  $started = $rows[0].Time.UtcDateTime.ToString('yyyy-MM-dd HH:mm', $inv); $ended = $rows[-1].Time.UtcDateTime.ToString('yyyy-MM-dd HH:mm', $inv)
  $subCalls = [int](($subs | Measure-Object Calls -Sum).Sum)
  $maxCtx = ($rows | Measure-Object Ctx -Maximum).Maximum
  $rebuildCost = ($reb | ForEach-Object { $w.CacheWrite * $_.CW } | Measure-Object -Sum).Sum
  $carryCost = ($s.Carriers | Measure-Object Carry -Sum).Sum
  $rulesTok = [int](($s.Rules | Measure-Object Tok -Sum).Sum)
  $compactions = @($rows | Where-Object Compact).Count
  $cacheShare = if ($cost) { 100 * $w.CacheRead * $cr / $cost } else { 0 }
  $d = $s.Duration
  $duration = if ($d) { [ordered]@{ wall = ConvertTo-RecordNumber $d.Wall; active = (ConvertTo-RecordNumber $d.Wall) - (ConvertTo-RecordNumber $d.Waiting); waiting = ConvertTo-RecordNumber $d.Waiting; waits = [int64]$d.Waits } } else { $null }

  # the flat summary read by Format-SessionProfile
  $row = [pscustomobject]@{
    WorkItem = $wi; Lane = $lane; Branch = $branch; Commit = $commit; Started = $started; Ended = $ended
    Version = $s.Version; Model = $s.Model; Account = $s.Account
    Calls = $rows.Count; HumanTurns = $s.Turns.Count; Subagents = $subs.Count; SubagentCalls = $subCalls
    # the main thread's own cost over its own calls; subagent calls are not in the denominator, so their cost is not in the numerator either
    CostUnits = Format-Num $cost; UnitsPerCall = Format-Num ($mainCost / $rows.Count); MainCost = Format-Num $mainCost; SubagentCost = Format-Num ($cost - $mainCost)
    CacheTtl = $s.CacheTtl; InputTok = $in; CacheReadTok = $cr; CacheWriteTok = $cw; OutTok = $out
    FirstCtx = $rows[0].Ctx; MaxCtx = $maxCtx; LastCtx = $rows[-1].Ctx
    First40UnitsPerCall = $(if ($p40.UnitsPerCall -ne '') { Format-Num $p40.UnitsPerCall } else { '' }); First40Ctx = $p40.Ctx
    First70UnitsPerCall = $(if ($p70.UnitsPerCall -ne '') { Format-Num $p70.UnitsPerCall } else { '' }); First70Ctx = $p70.Ctx
    IdleRebuilds = $reb.Count; IdleRebuildCost = Format-Num $rebuildCost; CarryCost = Format-Num $carryCost
    Duration = $duration
    TopCarriers = (($top | ForEach-Object { "$($_.Names)=$(Format-Num $_.Carry)" }) -join '; ')
    RulesLoaded = (($ruleSum.Keys | ForEach-Object { "$_=$($ruleSum[$_])" }) -join '; '); RulesTok = $rulesTok
  }

  $limitRecord = $null
  if ($limit.WeeklyStartPct -ne '') {
    $limitRecord = [ordered]@{
      startPct = ConvertTo-RecordNumber $limit.WeeklyStartPct 2; startAt = $limit.WeeklyStartAt
      endPct = ConvertTo-RecordNumber $limit.WeeklyEndPct 2; usedPct = ConvertTo-RecordNumber $limit.WeeklyUsedPct 2
      limitCost = ConvertTo-RecordNumber $limit.LimitCostUnits; unitsPerPct = ConvertTo-RecordNumber $limit.UnitsPerWeeklyPct
      reason = ConvertTo-RecordText $limit.Reason
    }
  }
  $record = [ordered]@{
    schema = 1; profiler = $profilerVersion
    session = $s.Id; workItem = ConvertTo-RecordText $wi; lane = ConvertTo-RecordText $lane; branch = ConvertTo-RecordText $branch
    commit = ConvertTo-RecordText $commit; author = ConvertTo-RecordText $author; profiled = $profiled; started = $started; ended = $ended; duration = $duration
    version = ConvertTo-RecordText $s.Version; model = ConvertTo-RecordText $s.Model; account = ConvertTo-RecordText $s.Account
    note = ConvertTo-RecordText $Note; marker = ConvertTo-RecordText $Marker
    calls = [int64]$rows.Count; humanTurns = [int64]$s.Turns.Count; subagents = [int64]$subs.Count; subagentCalls = [int64]$subCalls
    tokens = [ordered]@{ input = [int64]$in; cacheRead = [int64]$cr; cacheWrite = [int64]$cw; output = [int64]$out }
    weights = [ordered]@{ input = ConvertTo-RecordNumber $w.Input 4; cacheRead = ConvertTo-RecordNumber $w.CacheRead 4; cacheWrite = ConvertTo-RecordNumber $w.CacheWrite 4; output = ConvertTo-RecordNumber $w.Output 4 }
    cost = [ordered]@{ total = ConvertTo-RecordNumber $cost; main = ConvertTo-RecordNumber $mainCost; subagents = ConvertTo-RecordNumber ($cost - $mainCost) }
    cacheReadShare = ConvertTo-RecordNumber $cacheShare 1
    unitsPerCall = [ordered]@{ first40 = ConvertTo-RecordNumber $p40.UnitsPerCall; first70 = ConvertTo-RecordNumber $p70.UnitsPerCall; whole = ConvertTo-RecordNumber ($mainCost / $rows.Count) }
    context = [ordered]@{ first = [int64]$rows[0].Ctx; max = [int64]$maxCtx; last = [int64]$rows[-1].Ctx; first40 = ConvertTo-RecordNumber $p40.Ctx; first70 = ConvertTo-RecordNumber $p70.Ctx }
    cacheTtl = ConvertTo-RecordText $s.CacheTtl; compactions = [int64]$compactions
    idleRebuilds = [ordered]@{ count = [int64]$reb.Count; cost = ConvertTo-RecordNumber $rebuildCost }
    carryCost = ConvertTo-RecordNumber $carryCost
    diff = [ordered]@{ files = ConvertTo-RecordNumber $diff.Files; lines = ConvertTo-RecordNumber $diff.Lines }
    byActivity = @($byAct | ForEach-Object { [ordered]@{ activity = $_.Cat; calls = [int64]$_.Calls; cost = ConvertTo-RecordNumber $_.Cost } })
    subagentsByType = @($bySub | ForEach-Object { [ordered]@{ type = $_.Type; model = $_.Model; agents = [int64]$_.Agents; calls = [int64]$_.Calls; cost = ConvertTo-RecordNumber $_.Cost } })
    topCarriers = @($top | ForEach-Object { [ordered]@{ tools = $_.Names; cost = ConvertTo-RecordNumber $_.Carry } })
    rulesLoaded = @($ruleSum.Keys | ForEach-Object { [ordered]@{ rule = $_; tokens = [int64]$ruleSum[$_] } })
    rulesTokens = [int64]$rulesTok
    limit = $limitRecord
  }
  [pscustomobject]@{ Row = $row; Limit = $limit; Record = $record }
}

<#
.SYNOPSIS
  JSON text of a record: two-space indentation, LF line ends and a final line end, so that the same figures always
  give the same bytes.
#>
function ConvertTo-RecordJson($Record) { (($Record | ConvertTo-Json -Depth 8) -replace "`r`n", "`n") + "`n" }

<#
.SYNOPSIS
  Writes a record as UTF-8 without BOM; returns $true when the file content changed.
#>
function Write-SessionRecord($Record, [string]$Path) {
  $text = ConvertTo-RecordJson $Record
  # a checkout with core.autocrlf has CRLF line ends, which are the same record
  if ((Test-Path $Path) -and ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n") -ceq $text) { return $false }
  New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
  [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
  $true
}

<#
.SYNOPSIS
  Path of the record of a session: records/<UTC start date>_<session id>.json.
#>
function Get-RecordPath([string]$Id, [string]$Started) { Join-Path $recordsDir "$($Started.Substring(0, 10))_$Id.json" }

<#
.SYNOPSIS
  Rebuilds report.html from the records and opens it unless -NoOpen.
#>
function Update-Report {
  $file = Write-SessionReport $recordsDir $reportFile
  "Report: $file"
  if (-not $NoOpen) { Invoke-Item $file }
}

if ($Recompute) {
  if (-not (Test-Path $recordsDir)) { throw "No records at $recordsDir" }
  # what the transcript cannot tell again, or could only tell differently later
  $kept = 'workItem', 'lane', 'branch', 'commit', 'author', 'profiled', 'note', 'marker', 'diff'
  $changed = 0; $total = 0
  foreach ($f in (Get-ChildItem $recordsDir -File -Filter *.json | Sort-Object Name)) {
    $total++
    $old = ConvertFrom-JsonText ([IO.File]::ReadAllText($f.FullName))
    $file = Join-Path $TranscriptDir "$($old.session).jsonl"
    if (-not (Test-Path $file)) { "Kept $($old.session.Substring(0, 8)) as it is: no transcript."; continue }
    $until = [datetimeoffset]::new([datetime]::ParseExact([string]$old.ended, 'yyyy-MM-dd HH:mm', $inv), [TimeSpan]::Zero).AddMinutes(1).AddTicks(-1)
    # a record keeps the weights it was first costed with, so a change of the settings does not rewrite it; the
    # weights apply while the transcript is read, which prices every call
    $script:costWeights = Copy-CostWeights $defaultWeights
    if ($old.weights) { Set-CostWeights $old.weights }
    $parsed = Read-WorkSession (Get-Item $file) -Until $until @sessionOptions
    # the end time has minute precision, and the session can go on within the minute it was profiled in; the cut
    # falls just before the first call the record did not have, so the later lines of a split last response stay in
    $stored = [int]$old.calls
    if ($stored -gt 0 -and $parsed.Rows.Count -gt $stored) { $parsed = Read-WorkSession (Get-Item $file) -Until $parsed.Rows[$stored].Time.AddTicks(-1) @sessionOptions }
    $new = (New-SessionProfile $parsed).Record
    $script:costWeights = Copy-CostWeights $defaultWeights
    foreach ($k in $kept) {
      $v = $old.$k
      if ($k -eq 'diff') { $v = [ordered]@{ files = ConvertTo-RecordNumber $v.files; lines = ConvertTo-RecordNumber $v.lines } }
      $new[$k] = $v
    }
    # the stored readings are the only ones left when the transcript has none
    if ($null -eq $new.limit -and $null -ne $old.limit) {
      $l = $old.limit
      $new.limit = [ordered]@{ startPct = $l.startPct; startAt = $l.startAt; endPct = $l.endPct; usedPct = $l.usedPct; limitCost = $l.limitCost; unitsPerPct = $l.unitsPerPct; reason = $l.reason }
    }
    if ($new.calls -ne $stored) { "Note: $($old.session.Substring(0, 8)) has $($new.calls) calls up to its end time, the stored record $stored." }
    $path = Get-RecordPath $new.session $new.started
    if ($path -ne $f.FullName) { Remove-Item $f.FullName }
    if (Write-SessionRecord $new $path) { $changed++ }
  }
  "Recomputed $total records in $recordsDir with ${profilerVersion}: $changed changed."
  Update-Report
}
elseif ($Report) {
  Update-Report
}
else {
  $file = Resolve-SessionFile
  $parsed = Read-WorkSession $file @sessionOptions
  # without -Session the session profiled is the one running in this checkout (its own id, else the newest transcript)
  $current = if (-not $Session) { [string]((& git -C $repoRoot branch --show-current) | Select-Object -First 1) } else { '' }
  $p = New-SessionProfile $parsed $current
  Format-SessionProfile $parsed $p.Row $TopTurns $p.Limit
  ''
  if (-not $Save) {
    'Show only: nothing was written. Run again with save to record this session.'
    return
  }
  $existing = @(Get-ChildItem $recordsDir -File -Filter "*_$($parsed.Id).json" -ErrorAction SilentlyContinue)
  if ($existing.Count) { throw "Session $($parsed.Id) is already recorded in $($existing[0].FullName). Use -Recompute to refresh its figures." }
  $path = Get-RecordPath $parsed.Id $p.Record.started
  $null = Write-SessionRecord $p.Record $path
  "Saved session $($parsed.Id.Substring(0, 8)) to $path."
  Update-Report
}
