<#
.SYNOPSIS
  Checks Profile-Session.ps1 against the synthetic session in fixtures/session; exits 1 on the first failed check.
.DESCRIPTION
  Runs the profiler on copies of the fixture in a temporary folder, so no tracked file is written. The fixture has
  seven main-thread calls with hand-computed values: a response split over two lines, a placeholder without
  usage, a sidechain line, two human turns next to a meta message and a tool result, a gap of six minutes followed
  by a cache write of 40k, a compaction, a path-scoped rule loaded after the second call, a Read that grows the
  context by 29,995 tokens, two subagents (one under subagents/ with calls of two models, one under
  subagents/workflows/) and a fake organization id, whose account label is checked against a hash computed here.
  Variants made here cover a session
  that writes the one-hour cache, plan-usage readings (get_usage results) at the start, mid-session and at the end,
  a transcript that grew after it was profiled, a record without a transcript and the equal-length prefix figures.
  The report is checked for its embedded data only; the behaviour of the page is checked in a browser.
.EXAMPLE
  pwsh <skill folder>/scripts/tests/Test-ProfileSession.ps1
#>
$ErrorActionPreference = 'Stop'
$profiler = Join-Path $PSScriptRoot '../Profile-Session.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures/session'
$id = '0f1c7a2e-0000-4000-8000-000000000001'
$id2 = '0f1c7a2e-0000-4000-8000-000000000002'
$id3 = '0f1c7a2e-0000-4000-8000-000000000003'
$id4 = '0f1c7a2e-0000-4000-8000-000000000004'
$id5 = '0f1c7a2e-0000-4000-8000-000000000005'
$orgId = '00000000-0000-4000-8000-0000000000aa'
$orgId3 = '00000000-0000-4000-8000-0000000000bb'
$script:passed = 0

<#
.SYNOPSIS
  Records one check; throws with the message when the condition is false.
#>
function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "FAILED: $Message" }
  $script:passed++
}

<#
.SYNOPSIS
  Asserts that a value equals the expected one, comparing as strings.
#>
function Assert-Equal($Expected, $Actual, [string]$What) {
  Assert-True ([string]$Expected -eq [string]$Actual) "$What expected '$Expected' but was '$Actual'"
}

<#
.SYNOPSIS
  Account label of an organization id, computed independently of the profiler: "org-" and the first two bytes of
  its SHA-256 in lowercase hex.
#>
function Get-ExpectedLabel([string]$OrganizationId) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($OrganizationId)) } finally { $sha.Dispose() }
  'org-' + (($bytes[0..1] | ForEach-Object { $_.ToString('x2') }) -join '')
}

<#
.SYNOPSIS
  Creates an empty temporary folder and returns its path.
#>
function New-TempDir {
  $d = Join-Path ([IO.Path]::GetTempPath()) ('profile-session-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory $d | Out-Null
  $d
}

<#
.SYNOPSIS
  Runs the profiler in this process without opening the report and returns its output as text; a thrown error is
  returned as text with the prefix "ERROR:".
#>
# the user and repository settings files are pointed at a file that does not exist, so a run does not depend on the
# settings of the machine or of the repository the test is started from; a test that needs a layer passes its own file
$noSettings = Join-Path ([IO.Path]::GetTempPath()) 'profile-session-no-such-settings.json'
function Invoke-Profiler([hashtable]$Arguments, [object[]]$Positional = @()) {
  foreach ($k in 'UserConfig', 'RepoConfig') { if (-not $Arguments.ContainsKey($k)) { $Arguments[$k] = $noSettings } }
  try { (& $profiler @Positional @Arguments -NoOpen *>&1 | Out-String) }
  catch { "ERROR: $($_.Exception.Message)" }
}

<#
.SYNOPSIS
  Path of the record of a session in a results folder; $null when there is none.
#>
function Get-RecordFile([string]$ResultsDir, [string]$Session) {
  $f = @(Get-ChildItem (Join-Path $ResultsDir 'records') -File -Filter "*_$Session.json" -ErrorAction SilentlyContinue)
  if ($f.Count) { $f[0].FullName } else { $null }
}

<#
.SYNOPSIS
  The record of a session in a results folder, parsed.
#>
function Get-Record([string]$ResultsDir, [string]$Session) {
  $f = Get-RecordFile $ResultsDir $Session
  Assert-True ([bool]$f) "a record of $Session exists in $ResultsDir"
  Get-Content $f -Raw | ConvertFrom-Json
}

<#
.SYNOPSIS
  Hash of every file under a folder, keyed by name, to show that a run left them byte-identical.
#>
function Get-FolderHashes([string]$Dir) {
  $h = [ordered]@{}
  foreach ($f in (Get-ChildItem $Dir -File | Sort-Object Name)) { $h[$f.Name] = (Get-FileHash $f.FullName).Hash }
  ($h.Keys | ForEach-Object { "$_=$($h[$_])" }) -join ';'
}

<#
.SYNOPSIS
  Transcript lines of one get_usage tool call on the main thread and its result, as the Claude desktop app writes
  them: an assistant line without usage, so no model call is added, and a tool result, which is not a human turn.
.DESCRIPTION
  The weekly window carries the label with a middle dot, and a model-specific weekly window is listed before it, so
  the reading has to pick the window for all models.
#>
function New-UsageLines([string]$At, [int]$Weekly, [string]$ResetsAt = '2026-09-04T09:00:00Z') {
  $n = ++$script:usageN
  $dot = [char]0xB7
  $result = [ordered]@{ plan = [ordered]@{ status = 'ok'; windows = @(
        [ordered]@{ label = '5-hour limit'; percentUsed = 10; resetsAt = '2026-09-01T14:00:00Z' },
        [ordered]@{ label = "Weekly $dot Opus"; percentUsed = 99; resetsAt = $ResetsAt },
        [ordered]@{ label = "Weekly $dot all models"; percentUsed = $Weekly; resetsAt = $ResetsAt }) } } | ConvertTo-Json -Depth 6
  $use = [ordered]@{ isSidechain = $false; type = 'assistant'; timestamp = "$($At).000Z"; requestId = "ru$n"
    message = [ordered]@{ id = "mu$n"; model = 'claude-sonnet-5'; content = @([ordered]@{ type = 'tool_use'; id = "tu$n"; name = 'mcp__ccd_session_mgmt__get_usage'; input = @{} }) } }
  $res = [ordered]@{ isSidechain = $false; type = 'user'; timestamp = "$($At).500Z"
    message = [ordered]@{ role = 'user'; content = @([ordered]@{ type = 'tool_result'; tool_use_id = "tu$n"; content = @([ordered]@{ type = 'text'; text = $result }) }) } }
  ($use | ConvertTo-Json -Depth 8 -Compress), ($res | ConvertTo-Json -Depth 8 -Compress)
}

<#
.SYNOPSIS
  Runs one save of a copy of the fixture session with the given plan-usage readings appended and returns its
  record. A reading is a hashtable of New-UsageLines parameters.
#>
function Save-Case([object[]]$Readings = @()) {
  $res = New-TempDir; $dir = Join-Path $res 'transcripts'
  New-Item -ItemType Directory $dir | Out-Null
  Copy-Item (Join-Path $fixture $id) $dir -Recurse
  $lines = @(Get-Content (Join-Path $fixture "$id.jsonl")) + @(foreach ($r in $Readings) { New-UsageLines @r })
  Set-Content (Join-Path $dir "$id.jsonl") $lines -Encoding utf8
  $out = Invoke-Profiler @{ Session = $id; Save = $true; TranscriptDir = $dir; ResultsDir = $res; Lane = 'Feature' }
  Assert-True ($out -notmatch '^ERROR:') "save failed: $out"
  Get-Record $res $id
}

<#
.SYNOPSIS
  Saves the fixture session from a transcript folder into a results folder by its explicit id and returns the
  results folder.
#>
function Save-Into([string]$ResultsDir, [string]$TranscriptDir, [hashtable]$Extra = @{}) {
  $args1 = @{ Session = $id; Save = $true; TranscriptDir = $TranscriptDir; ResultsDir = $ResultsDir } + $Extra
  $out = Invoke-Profiler $args1
  Assert-True ($out -notmatch '^ERROR:') "save failed: $out"
  $ResultsDir
}
$work = New-TempDir
try {
  $transcripts = Join-Path $work 'transcripts'
  New-Item -ItemType Directory $transcripts | Out-Null
  Copy-Item (Join-Path $fixture "$id.jsonl") $transcripts
  Copy-Item (Join-Path $fixture $id) $transcripts -Recurse
  $label = Get-ExpectedLabel $orgId

  # ---- show only: the newest session is picked and nothing is written
  $results = Join-Path $work 'results'; $script:usageN = 0
  $out = Invoke-Profiler @{ TranscriptDir = $transcripts; ResultsDir = $results }
  Assert-True ($out -match "Session $id") "show-only run picks the newest session: $out"
  Assert-True ($out -match 'Main model calls: 7\s+human turns: 2\s+subagents: 2 \(3 calls\)') 'calls, turns and subagents on screen'
  Assert-True ($out -match 'TOTAL weighted cost: 165,446') 'total cost on screen'
  Assert-True ($out -match 'Duration: 7m active of 8m from the first human turn; 1m waiting for the user in 1 waits') 'duration on screen'
  Assert-True ($out -match "account $label") 'account label on screen'
  Assert-True ($out -notmatch $orgId) 'organization id not on screen'
  Assert-True ($out -match 'Show only: nothing was written') 'show-only notice'
  Assert-True (-not (Test-Path $results)) 'show-only run writes no file'

  # ---- save: one record with the hand-computed values, and the report
  $out = Invoke-Profiler @{ TranscriptDir = $transcripts; ResultsDir = $results; Lane = 'Feature'; Note = 'fixture' } @('save')
  Assert-True ($out -notmatch '^ERROR:') "save run: $out"
  $recordFile = Join-Path $results "records/2026-09-01_$id.json"
  Assert-True (Test-Path $recordFile) 'save writes records/<start date>_<session>.json'
  $report = Join-Path $results 'report.html'
  Assert-True (Test-Path $report) 'save writes report.html'
  $text = [IO.File]::ReadAllText($recordFile)
  Assert-True ($text -notmatch "`r") 'record has LF line ends'
  Assert-True ($text.StartsWith("{`n  `"schema`": 1,`n  `"profiler`": `"profile-session/7`",")) 'record starts with schema and profiler, two-space indented'
  Assert-True ([IO.File]::ReadAllBytes($recordFile)[0] -ne 0xEF) 'record has no BOM'
  $r = $text | ConvertFrom-Json
  $expected = [ordered]@{
    session = $id; workItem = '999'; lane = 'Feature'; branch = '#999'; version = '2.1.300'; model = 'claude-sonnet-5'; account = $label; note = 'fixture'; marker = ''
    started = '2026-09-01 10:00'; ended = '2026-09-01 10:08'
    calls = '7'; humanTurns = '2'; subagents = '2'; subagentCalls = '3'
    'cost.total' = '165446'; 'cost.main' = '155640'; 'cost.subagents' = '9806'; 'unitsPerCall.whole' = '22234'; 'unitsPerCall.first40' = ''; 'unitsPerCall.first70' = ''
    cacheReadShare = '11.8'; cacheTtl = ''
    'tokens.input' = '46'; 'tokens.cacheRead' = '195000'; 'tokens.cacheWrite' = '113000'; 'tokens.output' = '930'
    'weights.cacheRead' = '0.1'; 'weights.cacheWrite' = '1.25'
    'context.first' = '20010'; 'context.max' = '65005'; 'context.last' = '36005'; 'context.first40' = ''
    'duration.wall' = '480'; 'duration.active' = '432'; 'duration.waiting' = '48'; 'duration.waits' = '1'
    compactions = '1'; 'idleRebuilds.count' = '1'; 'idleRebuilds.cost' = '50000'; carryCost = '26097'; rulesTokens = '100'; limit = ''
  }
  foreach ($key in $expected.Keys) {
    $v = $r; foreach ($part in $key.Split('.')) { $v = $v.$part }
    Assert-Equal $expected[$key] $v $key
  }
  Assert-Equal 'explore (read/search):2:78265; build/test:1:40505; implement:1:17755; other subagent:1:9355; ship:1:6255; reply (no tools):1:3505' (($r.byActivity | ForEach-Object { "$($_.activity):$($_.calls):$($_.cost)" }) -join '; ') 'byActivity'
  Assert-Equal 'wi-planner/claude-opus-5:1:1:5203; skill-runner/claude-sonnet-5:1:1:2651; wi-planner/claude-sonnet-5:1:1:1952' (($r.subagentsByType | ForEach-Object { "$($_.type)/$($_.model):$($_.agents):$($_.calls):$($_.cost)" }) -join '; ') 'subagentsByType split by the model of each call'
  Assert-Equal 'Read=17997; Bash=5000; Edit=2000' (($r.topCarriers | ForEach-Object { "$($_.tools)=$($_.cost)" }) -join '; ') 'topCarriers'
  Assert-Equal 'csharp=100' (($r.rulesLoaded | ForEach-Object { "$($_.rule)=$($_.tokens)" }) -join '; ') 'rulesLoaded'
  Assert-True ($text -notmatch $orgId) 'organization id not in the record'

  # ---- a second save of the same session is rejected and leaves the record unchanged
  $before = Get-FolderHashes (Join-Path $results 'records')
  $out = Invoke-Profiler @{ Session = $id.Substring(0, 8); Save = $true; TranscriptDir = $transcripts; ResultsDir = $results }
  Assert-True ($out -match '^ERROR:.*already recorded') "duplicate save is rejected: $out"
  Assert-Equal $before (Get-FolderHashes (Join-Path $results 'records')) 'records after the rejected save'

  # ---- more sessions: another model with a marker, another account and version, and one without the account field
  ((Get-Content (Join-Path $fixture "$id.jsonl") -Raw) -replace $id, $id2 -replace 'claude-sonnet-5', 'claude-opus-5') | Set-Content (Join-Path $transcripts "$id2.jsonl") -NoNewline -Encoding utf8
  $out = Invoke-Profiler @{ Session = $id2; Save = $true; TranscriptDir = $transcripts; ResultsDir = $results; Lane = 'Feature'; Marker = 'rules-v2' }
  Assert-True ($out -notmatch '^ERROR:') "second session save: $out"
  Assert-Equal $before.Split(';')[0] (Get-FolderHashes (Join-Path $results 'records')).Split(';')[0] 'an earlier record is not touched by a later save'
  $r2 = Get-Record $results $id2
  Assert-Equal 'claude-opus-5' $r2.model 'model of the second session'
  Assert-Equal 'rules-v2' $r2.marker 'the marker is stored with the record'

  ((Get-Content (Join-Path $fixture "$id.jsonl") -Raw) -replace $id, $id3 -replace $orgId, $orgId3 -replace '2\.1\.300', '2.1.301') | Set-Content (Join-Path $transcripts "$id3.jsonl") -NoNewline -Encoding utf8
  $out = Invoke-Profiler @{ Session = $id3; Save = $true; TranscriptDir = $transcripts; ResultsDir = $results; Lane = 'Feature' }
  Assert-True ($out -notmatch '^ERROR:') "third session save: $out"
  $label3 = Get-ExpectedLabel $orgId3
  Assert-True ($label3 -ne $label) 'the two fake organization ids give different labels'
  Assert-Equal $label3 (Get-Record $results $id3).account 'other organization id: its own label'
  Assert-Equal '2.1.301' (Get-Record $results $id3).version 'version of the third session'

  $noOrg = @(Get-Content (Join-Path $fixture "$id.jsonl") | Where-Object { $_ -notmatch 'organizationUuid' } | ForEach-Object { $_ -replace $id, $id4 })
  Set-Content (Join-Path $transcripts "$id4.jsonl") $noOrg -Encoding utf8
  $out = Invoke-Profiler @{ Session = $id4; Save = $true; TranscriptDir = $transcripts; ResultsDir = $results; Lane = 'Feature' }
  Assert-True ($out -notmatch '^ERROR:') "session without organization id: $out"
  Assert-True ($out -match 'account \(unknown\)') 'no organization id: unknown account on screen'
  Assert-Equal '' (Get-Record $results $id4).account 'no organization id: empty account'

  # ---- the report embeds every record and nothing from outside
  $html = [IO.File]::ReadAllText($report)
  Assert-True ($html -match '(?s)<script id="session-data" type="application/json">(.*?)</script>') 'report has the data element'
  $embedded = @($Matches[1].Replace('<\/', '</') | ConvertFrom-Json)
  Assert-Equal 4 $embedded.Count 'report embeds every record'
  foreach ($e in $embedded) {
    $file = Get-RecordFile $results $e.session
    Assert-Equal ((Get-Content $file -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 8 -Compress) ($e | ConvertTo-Json -Depth 8 -Compress) "embedded record $($e.session.Substring(34))"
  }
  Assert-True ($html -notmatch $orgId -and $html -notmatch $orgId3) 'organization ids not in the report'
  Assert-True ($html -notmatch 'https?:|//cdn|src="//') 'no external URL in the report'
  Assert-True ($html -notmatch '/\*SESSION_DATA\*/') 'the data placeholder is replaced'

  # ---- a note with "</script>" cannot close the data element
  $res6 = New-TempDir
  $out = Invoke-Profiler @{ Session = $id; Save = $true; TranscriptDir = $transcripts; ResultsDir = $res6; Note = 'a </script> note' }
  $html6 = [IO.File]::ReadAllText((Join-Path $res6 'report.html'))
  Assert-True ($html6 -notmatch 'a </script> note' -and $html6 -match 'a <\\/script> note') 'a closing script tag in a note is escaped in the report'

  # ---- -Report rebuilds the page without touching the records
  $before = Get-FolderHashes (Join-Path $results 'records')
  Remove-Item $report
  $out = Invoke-Profiler @{ Report = $true; ResultsDir = $results; TranscriptDir = $transcripts }
  Assert-True (Test-Path $report) "-Report writes report.html: $out"
  Assert-Equal $before (Get-FolderHashes (Join-Path $results 'records')) 'records after -Report'

  # ---- -Recompute: unchanged records stay byte-identical, a transcript that grew after it was profiled is cut at the
  # end of its record, kept fields survive, and a record without a transcript is left as it is
  $mainFile = Join-Path $transcripts "$id.jsonl"
  $late = (Get-Content $mainFile | Where-Object { $_ -match '"timestamp":"2026-09-01T10:08:00' }) -replace '10:08:00', '10:30:00' -replace '"id":"m8"', '"id":"m99"' -replace '"requestId":"r8"', '"requestId":"r99"'
  Add-Content $mainFile $late -Encoding utf8
  Remove-Item (Join-Path $transcripts "$id4.jsonl")
  $out = Invoke-Profiler @{ Recompute = $true; TranscriptDir = $transcripts; ResultsDir = $results }
  Assert-True ($out -match 'Recomputed 4 records .*: 0 changed') "-Recompute run: $out"
  Assert-True ($out -match 'Kept 0f1c7a2e as it is: no transcript') 'a record without a transcript is kept'
  Assert-Equal $before (Get-FolderHashes (Join-Path $results 'records')) 'records after -Recompute of unchanged sessions'
  Assert-Equal 'fixture' (Get-Record $results $id).note 'the note survives -Recompute'
  Assert-Equal 'rules-v2' (Get-Record $results $id2).marker 'the marker survives -Recompute'

  # a record whose figures differ from the transcript is rewritten
  $f2 = Get-RecordFile $results $id2
  [IO.File]::WriteAllText($f2, ([IO.File]::ReadAllText($f2) -replace '"total": \d+', '"total": 1'), [Text.UTF8Encoding]::new($false))
  $out = Invoke-Profiler @{ Recompute = $true; TranscriptDir = $transcripts; ResultsDir = $results }
  Assert-True ($out -match ': 1 changed') "-Recompute rewrites a changed record: $out"
  Assert-Equal '155640' (Get-Record $results $id2).cost.total 'recomputed cost (the copy has no subagents)'

  # a checkout with CRLF line ends holds the same record
  [IO.File]::WriteAllText($f2, ([IO.File]::ReadAllText($f2) -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($false))
  $out = Invoke-Profiler @{ Recompute = $true; TranscriptDir = $transcripts; ResultsDir = $results }
  Assert-True ($out -match ': 0 changed') "-Recompute treats CRLF line ends as unchanged: $out"

  # ---- plan-limit figures from the get_usage results in the transcript; the readings are appended after the last
  # call, so they also show that their place in the file does not matter, only their time
  $c = Save-Case @(@{ At = '2026-09-01T10:00:02'; Weekly = 40 }, @{ At = '2026-09-01T10:04:00'; Weekly = 41 }, @{ At = '2026-09-01T10:08:30'; Weekly = 42; ResetsAt = '2026-09-04T08:59:59Z' })
  Assert-Equal '7' $c.calls 'readings add no model call'
  Assert-Equal '2' $c.humanTurns 'readings add no human turn'
  Assert-Equal '40' $c.limit.startPct 'readings: start from the first'
  Assert-Equal '42' $c.limit.endPct 'readings: end from the last, from the window for all models'
  Assert-Equal '2' $c.limit.usedPct 'readings: used'
  Assert-Equal '2026-09-01 10:00' $c.limit.startAt 'readings: time of the start reading'
  Assert-Equal '165446' $c.limit.limitCost 'start before the first call, end after the last: the whole cost is counted'
  Assert-Equal '82723' $c.limit.unitsPerPct 'readings: units per 1 %'

  # main calls from 10:07:10 on cost 52,755 + 3,505 + 9,355 + 6,255 and the subagents, all after 10:07, 9,806
  $c = Save-Case @(@{ At = '2026-09-01T10:07:00'; Weekly = 40 }, @{ At = '2026-09-01T10:08:30'; Weekly = 42 })
  Assert-Equal '81676' $c.limit.limitCost 'start mid-session: only the cost from the start reading on'
  Assert-Equal '40838' $c.limit.unitsPerPct 'start mid-session: units per 1 %'

  # main calls from 10:01:05 to 10:07:20 cost 17,755 + 52,755 + 3,505; the subagent calls all come after 10:07:25
  $c = Save-Case @(@{ At = '2026-09-01T10:01:00'; Weekly = 40 }, @{ At = '2026-09-01T10:07:25'; Weekly = 41 })
  Assert-Equal '74015' $c.limit.limitCost 'end mid-session: only the cost up to the end reading'

  $c = Save-Case
  Assert-True ($null -eq $c.limit) 'no reading: no limit'

  $c = Save-Case @(@{ At = '2026-09-01T10:00:02'; Weekly = 40 })
  Assert-Equal '40' $c.limit.startPct 'one reading: start kept'
  Assert-Equal '' "$($c.limit.endPct)$($c.limit.usedPct)$($c.limit.unitsPerPct)" 'one reading: end, used and units per 1 % empty'

  $c = Save-Case @(@{ At = '2026-09-01T10:00:02'; Weekly = 40 }, @{ At = '2026-09-01T10:08:30'; Weekly = 3; ResetsAt = '2026-09-11T09:00:00Z' })
  Assert-Equal '40' $c.limit.startPct 'window rolled over: start kept'
  Assert-Equal '' "$($c.limit.usedPct)$($c.limit.unitsPerPct)" 'window rolled over: used and units per 1 % empty'
  Assert-Equal 'the weekly window rolled over between start and end' $c.limit.reason 'window rolled over: reason recorded'

  $c = Save-Case @(@{ At = '2026-09-01T10:00:02'; Weekly = 40 }, @{ At = '2026-09-01T10:08:30'; Weekly = 38 })
  Assert-Equal '38' $c.limit.endPct 'end below start: end kept'
  Assert-Equal '' "$($c.limit.usedPct)$($c.limit.unitsPerPct)" 'end below start: used and units per 1 % empty'

  # ---- not human turns: a background-task notification, a compaction summary and local command output. An
  # AskUserQuestion answered after 8 seconds between two calls is a wait; one after the last call is outside the
  # duration, which ends at the last call
  $extra = @(
    '{"isSidechain":false,"type":"user","timestamp":"2026-09-01T10:00:30.000Z","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>done</task-notification>"}}',
    '{"isSidechain":false,"type":"user","timestamp":"2026-09-01T10:00:40.000Z","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued from a previous conversation."}}',
    '{"isSidechain":false,"type":"user","timestamp":"2026-09-01T10:00:50.000Z","message":{"role":"user","content":"<local-command-stdout>Set model</local-command-stdout>"}}',
    '{"isSidechain":false,"type":"assistant","timestamp":"2026-09-01T10:07:21.000Z","requestId":"rq0","message":{"id":"mq0","model":"claude-sonnet-5","content":[{"type":"tool_use","id":"tq0","name":"AskUserQuestion","input":{}}]}}',
    '{"isSidechain":false,"type":"user","timestamp":"2026-09-01T10:07:29.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tq0","content":"answered"}]}}',
    '{"isSidechain":false,"type":"assistant","timestamp":"2026-09-01T10:08:10.000Z","requestId":"rq1","message":{"id":"mq1","model":"claude-sonnet-5","content":[{"type":"tool_use","id":"tq1","name":"AskUserQuestion","input":{}}]}}',
    '{"isSidechain":false,"type":"user","timestamp":"2026-09-01T10:09:10.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tq1","content":"answered"}]}}')
  $res7 = New-TempDir; $dir7 = Join-Path $res7 'transcripts'
  New-Item -ItemType Directory $dir7 | Out-Null
  Set-Content (Join-Path $dir7 "$id.jsonl") (@(Get-Content (Join-Path $fixture "$id.jsonl")) + $extra) -Encoding utf8
  $out = Invoke-Profiler @{ Session = $id; Save = $true; TranscriptDir = $dir7; ResultsDir = $res7 }
  Assert-True ($out -notmatch '^ERROR:') "session with notifications: $out"
  $r7 = Get-Record $res7 $id
  Assert-Equal '2' $r7.humanTurns 'notifications, compaction summaries and local command output are no human turns'
  Assert-Equal '480' $r7.duration.wall 'duration ends at the last call'
  Assert-Equal '56' $r7.duration.waiting 'waiting: the gap before the second human turn and the AskUserQuestion wait within the duration'
  Assert-Equal '424' $r7.duration.active 'active: wall minus waiting'
  Assert-Equal '2' $r7.duration.waits 'two waits for the user'
  $before7 = Get-FolderHashes (Join-Path $res7 'records')
  $out = Invoke-Profiler @{ Recompute = $true; TranscriptDir = $dir7; ResultsDir = $res7 }
  Assert-Equal $before7 (Get-FolderHashes (Join-Path $res7 'records')) 'a recompute gives the same duration'

  # ---- a work-item branch is recorded as HEAD in the transcript: the work item comes from a git commit command of the
  # session, and without one stays empty (an explicit session id never falls back to the checked-out branch)
  $res8 = New-TempDir; $dir8 = Join-Path $res8 'transcripts'
  New-Item -ItemType Directory $dir8 | Out-Null
  $headLines = @(Get-Content (Join-Path $fixture "$id.jsonl") | ForEach-Object { $_ -replace '"gitBranch":"#999"', '"gitBranch":"HEAD"' })
  Set-Content (Join-Path $dir8 "$id.jsonl") $headLines -Encoding utf8
  Assert-Equal '' (Get-Record (Save-Into $res8 $dir8) $id).workItem 'branch HEAD and no commit: no work item'
  $commit = '{"isSidechain":false,"type":"assistant","timestamp":"2026-09-01T10:07:40.000Z","gitBranch":"HEAD","requestId":"rc1","message":{"id":"mc1","model":"claude-sonnet-5","content":[{"type":"tool_use","id":"tc1","name":"Bash","input":{"command":"git commit -q -m \"#321 Some title\n\n- Do it\""}}]}}'
  $res9 = New-TempDir; $dir9 = Join-Path $res9 'transcripts'
  New-Item -ItemType Directory $dir9 | Out-Null
  Set-Content (Join-Path $dir9 "$id.jsonl") ($headLines + $commit) -Encoding utf8
  Assert-Equal '321' (Get-Record (Save-Into $res9 $dir9) $id).workItem 'branch HEAD: work item from the git commit command of the session'
  # ---- one-hour cache: the six-minute gap is within the cache lifetime, so it is not a rebuild
  ((Get-Content (Join-Path $fixture "$id.jsonl") -Raw) -replace $id, $id5 -replace '"cache_creation_input_tokens":(\d+)', '"cache_creation_input_tokens":$1,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":$1}') | Set-Content (Join-Path $transcripts "$id5.jsonl") -NoNewline -Encoding utf8
  $res5 = New-TempDir
  $out = Invoke-Profiler @{ Session = $id5; Save = $true; TranscriptDir = $transcripts; ResultsDir = $res5; Lane = 'Feature' }
  Assert-True ($out -notmatch '^ERROR:') "one-hour cache session: $out"
  $r5 = Get-Record $res5 $id5
  Assert-Equal '1h' $r5.cacheTtl 'one-hour cache: lifetime recorded'
  Assert-Equal '0' $r5.idleRebuilds.count 'one-hour cache: a six-minute gap is no rebuild'

  # ---- settings layers: the repository file overrides the user file, which overrides the defaults; the work item
  # pattern, the command pattern, the results folder, the base branch, the plan glob and bad files
  . (Join-Path $PSScriptRoot '../lib/Session-Profile.ps1')
  $cfgA = New-TempDir
  function Write-Settings([string]$Name, $Object) { $p = Join-Path $cfgA $Name; $Object | ConvertTo-Json -Depth 6 | Set-Content $p -Encoding utf8; $p }
  $userCfg = Write-Settings 'user.json' @{ workItemPattern = @('^Z(\d+)') }
  $repoCfg = Write-Settings 'repo.json' @{ workItemPattern = @('^#(\d+)') }
  $resU = New-TempDir
  Assert-Equal '' (Get-Record (Save-Into $resU $dir9 @{ UserConfig = $userCfg }) $id).workItem 'user pattern replaces the default: the commit subject no longer matches'
  $resR = New-TempDir
  Assert-Equal '321' (Get-Record (Save-Into $resR $dir9 @{ UserConfig = $userCfg; RepoConfig = $repoCfg }) $id).workItem 'repository pattern overrides the user pattern'
  Assert-Equal 'KEY-12' (Find-WorkItem 'feature/KEY-12 add' @('(?:^|/)([A-Z]+-\d+)')) 'a pattern with a group returns the group'
  Assert-Equal '54' (Find-WorkItem '54-57-fix' @('^#(\d+)', '^(\d+)-')) 'the first matching pattern wins'
  Assert-Equal '#12' (Find-WorkItem 'x #12' @('#\d+')) 'a pattern without a group returns the whole match'

  $cmdLine = '{"type":"user","timestamp":"2026-09-01T09:59:00.000Z","isSidechain":false,"message":{"role":"user","content":"<command-name>/implement-work-item</command-name> <command-args>#555</command-args>"}}'
  $resC = New-TempDir; $dirC = Join-Path $resC 'transcripts'; New-Item -ItemType Directory $dirC | Out-Null
  Set-Content (Join-Path $dirC "$id.jsonl") (@($cmdLine) + $headLines) -Encoding utf8
  $cmdCfg = Write-Settings 'cmd.json' @{ workItemCommandPattern = '/implement-work-item|/implement-issues?' }
  Assert-Equal '555' (Get-Record (Save-Into $resC $dirC @{ RepoConfig = $cmdCfg }) $id).workItem 'work item from a slash command named in the settings'
  $resC2 = New-TempDir
  Assert-Equal '' (Get-Record (Save-Into $resC2 $dirC) $id).workItem 'without the command pattern a command gives no work item'

  $resD = New-TempDir
  $dirCfg = Write-Settings 'dir.json' @{ resultsDir = $resD }
  $out = Invoke-Profiler @{ Session = $id; Save = $true; TranscriptDir = $dir9; RepoConfig = $dirCfg }
  Assert-True ($out -notmatch '^ERROR:' -and (Test-Path (Join-Path $resD "records/2026-09-01_$id.json"))) "resultsDir of the settings is where the record is written: $out"

  $bad = @{
    'unknown key'      = @{ Body = '{ "wrkItem": 1 }'; Expect = "unknown setting 'wrkItem'" }
    'bad regex'        = @{ Body = '{ "workItemPattern": ["(unclosed"] }'; Expect = 'not a valid regular expression' }
    'wrong type'       = @{ Body = '{ "resultsDir": 5 }'; Expect = "'resultsDir' must be a text" }
    'rule without category' = @{ Body = '{ "activityRules": [ { "pattern": "x" } ] }'; Expect = "each activity rule needs" }
    'not json'         = @{ Body = '{ nope'; Expect = 'is not valid JSON' }
  }
  foreach ($name in $bad.Keys) {
    $p = Join-Path $cfgA "bad-$($name -replace ' ', '-').json"
    Set-Content $p $bad[$name].Body -Encoding utf8
    $out = Invoke-Profiler @{ Session = $id; TranscriptDir = $dir9; ResultsDir = (New-TempDir); RepoConfig = $p }
    Assert-True ($out -match 'ERROR:' -and $out.Contains($bad[$name].Expect) -and $out.Contains((Split-Path $p -Leaf))) "settings error '$name' names the file and the key: $out"
  }
  $rules = Read-SettingsFile (Write-Settings 'rules.json' @{ activityRules = @(@{ pattern = '^Bash:.*pytest'; category = 'build/test' }) })
  Assert-Equal 'build/test' $rules.activityRules[0].Category 'an activity rule is read'

  # sessions listed in a manifest of excludeSessionManifests are not picked as the newest session
  $idX = '0f1c7a2e-0000-4000-8000-0000000000ee'
  $dirX = New-TempDir
  Copy-Item (Join-Path $fixture "$id.jsonl") (Join-Path $dirX "$id.jsonl")
  ((Get-Content (Join-Path $fixture "$id.jsonl") -Raw) -replace $id, $idX) | Set-Content (Join-Path $dirX "$idX.jsonl") -Encoding utf8
  (Get-Item (Join-Path $dirX "$id.jsonl")).LastWriteTimeUtc = [datetime]'2026-09-01T11:00:00Z'
  (Get-Item (Join-Path $dirX "$idX.jsonl")).LastWriteTimeUtc = [datetime]'2026-09-01T12:00:00Z'
  $manDir = Join-Path $cfgA 'runs'; New-Item -ItemType Directory $manDir | Out-Null
  Set-Content (Join-Path $manDir 'run1_manifest.json') (@{ sessions = @(@{ session = $idX }) } | ConvertTo-Json -Depth 4) -Encoding utf8
  $manCfg = Write-Settings 'manifest.json' @{ excludeSessionManifests = @($manDir) }
  Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirX }) -match "Session $idX") 'without the setting the newest transcript is picked'
  Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirX; RepoConfig = $manCfg }) -match "Session $id") 'a session listed in a manifest is skipped'

  # ---- the session the skill runs in: -CurrentSession, then CLAUDE_CODE_SESSION_ID, then the newest transcript
  $dirS = New-TempDir
  Copy-Item (Join-Path $fixture "$id.jsonl") (Join-Path $dirS "$id.jsonl")
  ((Get-Content (Join-Path $fixture "$id.jsonl") -Raw) -replace $id, $idX) | Set-Content (Join-Path $dirS "$idX.jsonl") -Encoding utf8
  (Get-Item (Join-Path $dirS "$id.jsonl")).LastWriteTimeUtc = [datetime]'2026-09-01T11:00:00Z'
  (Get-Item (Join-Path $dirS "$idX.jsonl")).LastWriteTimeUtc = [datetime]'2026-09-01T12:00:00Z'
  $savedEnv = $env:CLAUDE_CODE_SESSION_ID
  try {
    $env:CLAUDE_CODE_SESSION_ID = ''
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS }) -match "Session $idX") 'no current session: the newest transcript'
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS; CurrentSession = $id }) -match "Session $id") '-CurrentSession picks its transcript although another is newer'
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS; CurrentSession = '${CLAUDE_SESSION_ID}' }) -match "Session $idX") 'an unsubstituted -CurrentSession is ignored'
    $env:CLAUDE_CODE_SESSION_ID = $id
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS }) -match "Session $id") 'CLAUDE_CODE_SESSION_ID picks its transcript when -CurrentSession is empty'
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS; CurrentSession = $idX }) -match "Session $idX") '-CurrentSession wins over the environment'
    $out = Invoke-Profiler @{ TranscriptDir = $dirS; CurrentSession = '0f1c7a2e-0000-4000-8000-0000000000ff' }
    Assert-True ($out -match 'has no transcript' -and $out -match "Session $id") 'an id without a transcript warns and falls back to the environment id'
    Assert-True ((Invoke-Profiler @{ TranscriptDir = $dirS; Session = $idX.Substring(0, 35); CurrentSession = $id }) -match "Session $idX") 'an explicit session id wins over the current session'
  } finally { $env:CLAUDE_CODE_SESSION_ID = $savedEnv }

  # ---- activity classification: stack-independent built-in rules, the rules of the settings tried first
  foreach ($case in @(
      @('Bash:npm test', 'build/test'), @('Bash:pytest -q', 'build/test'), @('Bash:cargo test --all', 'build/test'),
      @('Bash:cd app && make all', 'build/test'), @('Bash:dotnet test Src/x.slnx', 'build/test'),
      @("Bash:sed -i 's/a/b/' f && echo to make a row", 'bash (other)'),
      @('Bash:gh pr create', 'ship'), @('Bash:git commit -m x', 'ship'), @('Bash:npx playwright test', 'e2e'),
      @('Agent:Plan', 'plan'), @('Agent:custom-helper', 'other subagent'), @('Skill:anything', 'skill load'),
      @('Write:docs/a.md', 'implement'), @('mcp__x__y', 'other tool'))) {
    Assert-Equal $case[1] (Get-ActivityCategory @($case[0])) "built-in category of $($case[0])"
  }
  $own = @([pscustomobject]@{ Pattern = '^Bash:npm test'; Category = 'e2e' }, [pscustomobject]@{ Pattern = 'deploy\.sh'; Category = 'deploy' })
  Assert-Equal 'e2e' (Get-ActivityCategory @('Bash:npm test') $own) 'a rule of the settings wins over the built-in one'
  Assert-Equal 'deploy' (Get-ActivityCategory @('Read', 'Bash:./deploy.sh') $own) 'a category named only by a rule outranks reading'
  Assert-Equal 'implement' (Get-ActivityCategory @('Edit:a.cs', 'Bash:./deploy.sh') $own) 'a category named only by a rule ranks below implement'
  $planCfg = Write-Settings 'plan.json' @{ activityRules = @(@{ pattern = '^Agent:wi-planner'; category = 'plan' }) }
  $resP = New-TempDir
  $rP = Get-Record (Save-Into $resP $transcripts @{ RepoConfig = $planCfg }) $id
  Assert-True (($rP.byActivity | Where-Object { $_.activity -eq 'plan' }).calls -eq 1) 'an activity rule of the settings reaches the record'

  # ---- a commit message passed as a here-document, the usual form in a session, gives its first line
  $heredoc = $commit | ConvertFrom-Json
  $heredoc.message.content[0].input.command = "cd repo && git commit -m `"`$(cat <<'EOF'`n#654 Fix the thing`n`n- detail`nEOF`n)`""
  $resH = New-TempDir; $dirH = Join-Path $resH 'transcripts'; New-Item -ItemType Directory $dirH | Out-Null
  Set-Content (Join-Path $dirH "$id.jsonl") ($headLines + ($heredoc | ConvertTo-Json -Depth 12 -Compress)) -Encoding utf8
  Assert-Equal '654' (Get-Record (Save-Into $resH $dirH) $id).workItem 'work item from the first line of a here-document commit message'

  # ---- waits that overlap count once
  $t0 = [datetimeoffset]'2026-09-01T10:00:00Z'
  $spans = @(@($t0.AddSeconds(10), $t0.AddSeconds(50)), @($t0.AddSeconds(40), $t0.AddSeconds(70)), @($t0.AddSeconds(80), $t0.AddSeconds(120)))
  $dur = Get-SessionDuration $t0 $t0.AddSeconds(100) $spans
  Assert-Equal '80' $dur.Waiting 'overlapping waits: the union of 10-70 s and 80-100 s'
  Assert-Equal '2' $dur.Waits 'overlapping waits merge into one'
  $one = Get-SessionDuration $t0 $t0.AddSeconds(100) @(,@($t0.AddSeconds(10), $t0.AddSeconds(50)))
  Assert-Equal '40' $one.Waiting 'a single wait'
  Assert-Equal '0' (Get-SessionDuration $t0 $t0.AddSeconds(100) @()).Waiting 'no wait'

  # ---- the PowerShell tool is read like the Bash tool: a here-string commit message gives the work item and the
  # command is classified by the same rules
  $viaTool = @{}
  foreach ($tool in 'Bash', 'PowerShell') {
    $line = $commit | ConvertFrom-Json
    $line.message.content[0].name = $tool
    $line.message.content[0].input.command = "git commit -m @'`n#777 Fix the thing`n`n- detail`n'@"
    $resT = New-TempDir; $dirT = Join-Path $resT 'transcripts'; New-Item -ItemType Directory $dirT | Out-Null
    Set-Content (Join-Path $dirT "$id.jsonl") ($headLines + ($line | ConvertTo-Json -Depth 12 -Compress)) -Encoding utf8
    $viaTool[$tool] = Get-Record (Save-Into $resT $dirT) $id
  }
  Assert-Equal '777' $viaTool.PowerShell.workItem 'work item from a PowerShell here-string commit message'
  Assert-Equal '777' $viaTool.Bash.workItem 'work item from a Bash here-string commit message'
  $acts = { param($r) ($r.byActivity | ForEach-Object { "$($_.activity):$($_.calls)" }) -join '; ' }
  $dirB = New-TempDir; $dirP = New-TempDir
  $allLines = @(Get-Content (Join-Path $fixture "$id.jsonl"))
  Set-Content (Join-Path $dirB "$id.jsonl") $allLines -Encoding utf8
  Set-Content (Join-Path $dirP "$id.jsonl") @($allLines | ForEach-Object { $_ -replace '"name":"Bash"', '"name":"PowerShell"' }) -Encoding utf8
  Assert-True (($allLines -join "`n") -match '"name":"Bash"') 'the fixture has Bash calls to turn into PowerShell calls'
  Assert-Equal (& $acts (Get-Record (Save-Into (New-TempDir) $dirB) $id)) (& $acts (Get-Record (Save-Into (New-TempDir) $dirP) $id)) 'PowerShell calls are classified like the same Bash calls'

  # base branch and the branch of the work item, in a temporary git repository
  $repoT = New-TempDir
  function Invoke-Git { & git -C $repoT -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false @args *>&1 | Out-Null }
  Invoke-Git init -b main
  Invoke-Git commit --allow-empty -m 'first'
  Assert-Equal 'main' (Resolve-BaseBranch $repoT '') 'base branch: main when it is the only candidate'
  Invoke-Git branch develop
  Assert-Equal 'develop' (Resolve-BaseBranch $repoT '') 'base branch: develop is preferred to main'
  Assert-Equal 'other' (Resolve-BaseBranch $repoT 'other') 'base branch: the configured one wins'
  Invoke-Git branch -D develop
  Invoke-Git branch -m main trunk
  Assert-Equal '' (Resolve-BaseBranch $repoT '') 'base branch: empty when no candidate exists'
  Invoke-Git branch -m trunk main
  Invoke-Git update-ref refs/remotes/origin/trunk HEAD
  Invoke-Git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  Assert-Equal 'origin/trunk' (Resolve-BaseBranch $repoT '') 'base branch: origin/HEAD when no local branch of that name exists'
  Invoke-Git branch trunk
  Assert-Equal 'trunk' (Resolve-BaseBranch $repoT '') 'base branch: the local branch of origin/HEAD, so a session on it has no change size'
  Assert-Equal '' (Get-DiffSize $repoT 'trunk' (Resolve-BaseBranch $repoT '')).Files 'base branch: no change size for the detected base branch itself'
  Invoke-Git branch -D trunk
  Invoke-Git symbolic-ref --delete refs/remotes/origin/HEAD
  Invoke-Git update-ref -d refs/remotes/origin/trunk
  Invoke-Git switch -c 54-fix
  New-Item -ItemType Directory (Join-Path $repoT 'plans') | Out-Null
  Set-Content (Join-Path $repoT 'plans/bug-54-x.md') 'plan' -Encoding utf8
  Invoke-Git add -A
  Invoke-Git commit -m 'second'
  $gitCfg = Write-Settings 'git.json' @{ workItemPattern = @('^(\d+)-'); lanePlanGlob = 'plans/*-{id}-*.md' }
  $resG = New-TempDir
  Push-Location $repoT
  try { $out = Invoke-Profiler @{ Save = $true; TranscriptDir = $dir8; ResultsDir = $resG; RepoConfig = $gitCfg } } finally { Pop-Location }
  Assert-True ($out -notmatch '^ERROR:') "profile in another repository: $out"
  $rg = Get-Record $resG $id
  Assert-Equal '54' $rg.workItem 'another repository: work item from the checked-out branch by the branch pattern'
  Assert-Equal '54-fix' $rg.branch 'another repository: branch'
  Assert-Equal 'Bug' $rg.lane 'another repository: lane from the plan glob'
  Assert-Equal '1' $rg.diff.files 'another repository: change size against the detected base branch'
  Assert-True ([bool]$rg.commit) 'another repository: the commit of the branch is stored'
  $resN = New-TempDir
  Push-Location $repoT
  try { $out = Invoke-Profiler @{ Save = $true; TranscriptDir = $dir8; ResultsDir = $resN; RepoConfig = $gitCfg; NoCommit = $true } } finally { Pop-Location }
  $rn = Get-Record $resN $id
  Assert-Equal $null $rn.commit '-NoCommit: no commit for a record that is amended into the current commit'
  Assert-Equal '54-fix' $rn.branch '-NoCommit: the branch is still stored'

  # ---- cost weights from the settings: a record stores the weights it was costed with, a bad value is refused, and
  # -Recompute keeps the weights of the record even when the settings changed
  $cfgDir = New-TempDir
  $cfg = Join-Path $cfgDir 'defaults.json'
  Set-Content $cfg '{ "costWeights": { "output": 10 } }' -Encoding utf8
  $res10 = New-TempDir
  $out = Invoke-Profiler @{ Session = $id5; Save = $true; TranscriptDir = $transcripts; ResultsDir = $res10; Lane = 'Feature'; DefaultsFile = $cfg }
  Assert-True ($out -notmatch '^ERROR:') "save with custom weights: $out"
  $r10 = Get-Record $res10 $id5
  Assert-Equal '10' $r10.weights.output 'custom weight is stored in the record'
  Assert-Equal '1' $r10.weights.input 'a weight the settings do not name keeps its default'
  Assert-Equal $r5.tokens.output $r10.tokens.output 'token totals do not depend on the weights'
  Assert-Equal ([Math]::Round($r5.cost.total + 5 * $r5.tokens.output, 2)) ([Math]::Round($r10.cost.total, 2)) 'cost units follow the output weight'
  Set-Content $cfg '{ "costWeights": { "output": -1 } }' -Encoding utf8
  Assert-True ((Invoke-Profiler @{ Session = $id5; TranscriptDir = $transcripts; ResultsDir = (New-TempDir); DefaultsFile = $cfg }) -match 'ERROR:.*output.*zero or more') 'a negative weight is refused'
  Set-Content $cfg '{ "costWeights": { "outpt": 2 } }' -Encoding utf8
  Assert-True ((Invoke-Profiler @{ Session = $id5; TranscriptDir = $transcripts; ResultsDir = (New-TempDir); DefaultsFile = $cfg }) -match "ERROR:.*Unknown cost weight 'outpt'") 'an unknown weight name is refused'
  Set-Content $cfg '{ "costWeights": { "output": 10 } }' -Encoding utf8
  $beforeW = Get-FolderHashes (Join-Path $res5 'records')
  $out = Invoke-Profiler @{ Recompute = $true; TranscriptDir = $transcripts; ResultsDir = $res5; DefaultsFile = $cfg }
  Assert-True ($out -match 'Recomputed 1 records .*: 0 changed') "-Recompute keeps the weights of the record: $out"
  Assert-Equal $beforeW (Get-FolderHashes (Join-Path $res5 'records')) 'record bytes after -Recompute under other weights'
  Assert-True ([IO.File]::ReadAllText((Join-Path $res10 'report.html')) -match 'cost weights') 'the report flags a change of cost weights'

  # ---- equal-length prefix: the first three calls cost 25,510 + 40,505 + 17,755
  . (Join-Path $PSScriptRoot '../lib/Session-Profile.ps1')
  $parsed = Read-WorkSession (Get-Item (Join-Path $fixture "$id.jsonl"))
  $p3 = Get-PrefixMetrics $parsed.Rows 3
  Assert-Equal '27923' ([Math]::Round($p3.UnitsPerCall)) 'prefix: units per call over the first three calls'
  Assert-Equal '60005' $p3.Ctx 'prefix: context of the third call'
  Assert-Equal '' (Get-PrefixMetrics $parsed.Rows 40).UnitsPerCall 'prefix longer than the session is empty'

  "All $script:passed checks passed."
} catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  exit 1
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'profile-session-test-*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
