# Parses one finished Claude Code session (main thread plus subagents) into a profile: model calls, human turns,
# weighted cost, context growth, idle cache rebuilds, compactions, carrying cost of what was added to the context,
# and path-scoped rules loaded. Token totals and context sizes come from API usage; the activity of a call is
# inferred from its tools.
. (Join-Path $PSScriptRoot 'Settings.ps1')

$script:pinv = [Globalization.CultureInfo]::InvariantCulture

# Built-in classification rules, tried in this order after the rules of the settings; the pattern is matched against
# a tag of a call (see Get-ActivityCategory). They cover tools and commands that do not depend on a stack or workflow.
$script:builtinActivityRules = @(
  [pscustomobject]@{ Pattern = '^Bash:.*(git (commit|push|switch -c|checkout -b)|gh (pr|issue))'; Category = 'ship' }
  [pscustomobject]@{ Pattern = '^Bash:.*(playwright|cypress)'; Category = 'e2e' }
  [pscustomobject]@{ Pattern = '^Bash:.*dotnet (build|test|msbuild)|^Bash:(.*(&&|;|\|)\s*)?((npm|pnpm|yarn)( run)? (test|build|lint)|python -m pytest|pytest|cargo (build|test)|go (build|test)|mvn|gradle|make)\b'; Category = 'build/test' }
  [pscustomobject]@{ Pattern = '^Edit:|^NotebookEdit'; Category = 'implement' }
  [pscustomobject]@{ Pattern = '^Write:'; Category = 'implement' }
  [pscustomobject]@{ Pattern = 'playwright|Claude_Browser|claude-in-chrome'; Category = 'browser verify' }
  [pscustomobject]@{ Pattern = '^Agent:Plan|^AskUserQuestion|ExitPlanMode|EnterPlanMode'; Category = 'plan' }
  [pscustomobject]@{ Pattern = '^Agent:'; Category = 'other subagent' }
  [pscustomobject]@{ Pattern = '^Skill:'; Category = 'skill load' }
  [pscustomobject]@{ Pattern = '^(Read|Grep|Glob)$|ToolSearch'; Category = 'explore (read/search)' }
  [pscustomobject]@{ Pattern = '^Bash:'; Category = 'bash (other)' }
)

# Order in which the categories of one call compete: the first present wins. A category named only by a rule of the
# settings ranks right after 'implement'.
$script:activityPriority = 'ship', 'e2e', 'build/test', 'implement', 'browser verify', 'plan', 'other subagent', 'skill load', 'ado read', 'explore (read/search)', 'bash (other)', 'other tool'

function Get-ActivityCategory {
  <#
  .SYNOPSIS
    Classifies one model call by the tools it used; a call with several tools takes the highest-priority category.
  .PARAMETER Tags
    Tool tags of the call: the tool name, extended with the command for Bash and PowerShell (both tagged Bash:), the subagent type for Agent, the skill
    for Skill and the file path for Write and Edit.
  .PARAMETER Rules
    Rules of the settings (objects with Pattern and Category), tried in order before the built-in rules; the first
    rule whose pattern matches a tag gives that tag's category.
  #>
  param([string[]]$Tags, [object[]]$Rules = @())
  if (-not $Tags -or $Tags.Count -eq 0) { return 'reply (no tools)' }
  $all = @($Rules) + $script:builtinActivityRules
  $cats = @()
  foreach ($t in $Tags) {
    $hit = $all | Where-Object { $t -match $_.Pattern } | Select-Object -First 1
    $cats += if ($hit) { $hit.Category } else { 'other tool' }
  }
  foreach ($p in $script:activityPriority[0..3]) { if ($cats -contains $p) { return $p } }
  $custom = @($cats | Where-Object { $_ -notin $script:activityPriority } | Select-Object -First 1)
  if ($custom.Count) { return $custom[0] }
  foreach ($p in $script:activityPriority[4..($script:activityPriority.Count - 1)]) { if ($cats -contains $p) { return $p } }
  'other tool'
}

function Get-UsageTokens {
  <#
  .SYNOPSIS
    Returns the input, output, cache-read and cache-write token counts of one API usage object.
  #>
  param($Usage)
  [pscustomobject]@{
    In = [int64]$Usage.input_tokens; Out = [int64]$Usage.output_tokens
    CR = [int64]$Usage.cache_read_input_tokens; CW = [int64]$Usage.cache_creation_input_tokens
  }
}

function Get-CacheLifetime {
  <#
  .SYNOPSIS
    Lifetime in seconds of the cache entries one API usage object wrote: 3600 for the one-hour cache, 300 for the
    five-minute cache, $null when the usage does not say (no cache write, or a transcript without the breakdown).
  #>
  param($Usage)
  $cc = $Usage.cache_creation
  if (-not $cc) { return $null }
  if ([int64]$cc.ephemeral_1h_input_tokens -gt 0) { return 3600 }
  if ([int64]$cc.ephemeral_5m_input_tokens -gt 0) { return 300 }
  $null
}

function Read-SubagentTranscripts {
  <#
  .SYNOPSIS
    Reads every subagent transcript under <session>/subagents (including nested folders such as workflows/) and
    returns one record per subagent with its type, calls, token totals and the time, cost and model of each call.
  .DESCRIPTION
    The subagent type comes from the .meta.json file next to the transcript. A response split over several lines is
    counted once (by message id and request id); placeholder responses without context are skipped.
  .PARAMETER Until
    Calls after this instant are left out, so a profile can be recomputed for the period it first covered.
  #>
  param([string]$Dir, [Nullable[datetimeoffset]]$Until)
  $out = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path $Dir)) { return $out }
  foreach ($f in (Get-ChildItem $Dir -Recurse -File -Filter *.jsonl | Sort-Object FullName)) {
    $metaPath = $f.FullName -replace '\.jsonl$', '.meta.json'
    $type = 'unknown'
    if (Test-Path $metaPath) { $m = Get-Content $metaPath -Raw | ConvertFrom-Json; if ($m.agentType) { $type = [string]$m.agentType } }
    $seen = @{}; $in = 0; $outTok = 0; $cr = 0; $cw = 0; $n = 0
    $callCosts = New-Object System.Collections.Generic.List[object]
    foreach ($line in [IO.File]::ReadLines($f.FullName)) {
      if ($line.Length -lt 20 -or $line.IndexOf('"usage"') -lt 0) { continue }
      $o = $line | ConvertFrom-Json
      if ($o.type -ne 'assistant' -or -not $o.message.usage) { continue }
      $k = "$($o.message.id)|$($o.requestId)"
      if ($seen.ContainsKey($k)) { continue }
      $seen[$k] = 1
      $time = [datetimeoffset]$o.timestamp
      if ($null -ne $Until -and $time -gt $Until) { continue }
      $u = Get-UsageTokens $o.message.usage
      if ($u.In + $u.CR + $u.CW -eq 0) { continue }
      $in += $u.In; $outTok += $u.Out; $cr += $u.CR; $cw += $u.CW; $n++
      $callCosts.Add([pscustomobject]@{ Time = $time; Cost = (Get-CostUnits $u.In $u.CR $u.CW $u.Out); Model = [string]$o.message.model })
    }
    # a subagent whose calls all fall after the cut was started after the period being profiled
    if ($null -ne $Until -and $n -eq 0) { continue }
    $out.Add([pscustomobject]@{ Type = $type; Calls = $n; In = $in; Out = $outTok; CR = $cr; CW = $cw; Cost = (Get-CostUnits $in $cr $cw $outTok); CallCosts = $callCosts.ToArray() })
  }
  $out
}

function Get-SubagentsByModel {
  <#
  .SYNOPSIS
    Groups the subagent calls of a session by subagent type and model, most expensive group first.
  .DESCRIPTION
    Calls and cost are split by the model of each call, so they add up exactly; a subagent that used several models
    counts in Agents of each of them. A subagent with one model contributes its total cost rather than the sum of its
    call costs, which can differ from it in the last floating-point digit.
  .PARAMETER Subagents
    Records returned by Read-SubagentTranscripts.
  #>
  param([object[]]$Subagents)
  $parts = foreach ($sub in $Subagents) {
    $groups = @($sub.CallCosts | Group-Object Model)
    foreach ($g in $groups) {
      $cost = if ($groups.Count -eq 1) { $sub.Cost } else { ($g.Group | Measure-Object Cost -Sum).Sum }
      [pscustomobject]@{ Type = $sub.Type; Model = $g.Name; Calls = $g.Count; Cost = $cost }
    }
  }
  @($parts | Group-Object Type, Model | ForEach-Object {
      [pscustomobject]@{ Type = $_.Group[0].Type; Model = $_.Group[0].Model; Agents = $_.Count
        Calls = ($_.Group | Measure-Object Calls -Sum).Sum; Cost = ($_.Group | Measure-Object Cost -Sum).Sum }
    } | Sort-Object @{ Expression = 'Cost'; Descending = $true }, @{ Expression = 'Type'; Descending = $true }, Model)
}

function Get-AccountLabel {
  <#
  .SYNOPSIS
    Short label of the account a session ran under: "org-" and the first four hex digits of the SHA-256 of its
    organization id.
  .DESCRIPTION
    Only the hash prefix is kept, so the organization id itself is never written anywhere; four hex digits tell a
    handful of accounts apart without identifying any of them.
  #>
  param([Parameter(Mandatory)][string]$OrganizationId)
  $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($OrganizationId))
  'org-' + ([Convert]::ToHexString($hash).Substring(0, 4).ToLowerInvariant())
}

function ConvertFrom-JsonText {
  <#
  .SYNOPSIS
    Parses JSON text, keeping timestamps as the strings written in it where the host supports that.
  #>
  param([string]$Text)
  $opt = @{}
  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $opt.DateKind = 'String' }
  $Text | ConvertFrom-Json @opt
}

function Get-UsageReading {
  <#
  .SYNOPSIS
    Reads one plan-limit reading from the result of a get_usage tool call; $null when the result has no weekly window.
  .DESCRIPTION
    The result is the JSON text the Claude desktop app returns: plan.windows holds one entry per limit window with
    label, percentUsed and resetsAt. The weekly window is the one whose label starts with "Weekly", preferring the
    one for all models when there are several; the five-hour window is the one whose label starts with "5-hour".
  .PARAMETER Content
    Content of the tool_result block: a string or a list of text blocks.
  .PARAMETER Time
    Time of the transcript line that holds the result.
  #>
  param($Content, [datetimeoffset]$Time)
  $text = if ($Content -is [string]) { $Content } else { (@($Content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join '') }
  try { $doc = ConvertFrom-JsonText $text } catch { return $null }
  $windows = @($doc.plan.windows | Where-Object { $_.label -and $null -ne $_.percentUsed })
  $weekly = @($windows | Where-Object { $_.label -match '^Weekly' } | Sort-Object { $_.label -notmatch 'all models' })
  if (-not $weekly.Count) { return $null }
  $five = @($windows | Where-Object { $_.label -match '^5-hour' })
  [pscustomobject]@{
    Time = $Time; WeeklyPct = [double]$weekly[0].percentUsed; WeeklyResetsAt = $weekly[0].resetsAt
    FiveHourPct = $(if ($five.Count) { [double]$five[0].percentUsed } else { $null })
  }
}

function Read-WorkSession {
  <#
  .SYNOPSIS
    Parses one session transcript and its subagents into a profile object.
  .DESCRIPTION
    Main-thread lines marked isSidechain are skipped; a response split over several lines is merged into one call
    by message id and request id, keeping the usage of its first line; calls without any context (interrupted or
    synthetic placeholders) are dropped.
    An idle cache rebuild is a call that follows a gap longer than the lifetime of the cache the session writes
    and writes more than 30k tokens to the cache; the lifetime is read from the cache-write breakdown of the
    earlier calls (one hour or five minutes), with GapSeconds as the fallback for transcripts without it. A
    compaction is a call whose context is below 0.6 of the previous call's context of over 50k. The carrying cost
    of a call is the context growth it caused, re-read at the cache-read weight by every later call. A human turn
    comes from a person: origin "human" where the transcript records one, never a compaction summary, a
    background-task notification, local command output or an interruption marker. The duration runs from the first
    human turn to the last main-thread call; the time waiting for the user is the gap between the last
    assistant line and each later human turn, plus the time an AskUserQuestion or ExitPlanMode call waited for its
    answer. The account is the label of the first organizationUuid in the transcript; empty when the transcript has none. Every result
    of a get_usage tool call on the main thread is a plan-limit reading (UsageReadings, in time order).
  .PARAMETER File
    The session transcript (<session id>.jsonl).
  .PARAMETER GapSeconds
    Cache lifetime assumed while no earlier call has shown which cache the session writes.
  .PARAMETER WorkItemPatterns
    Regular expressions tried in order on the subject of each git commit command; the first group (or the whole match)
    is the work item.
  .PARAMETER WorkItemCommandPattern
    Regular expression of the name of a slash command that takes a work item id as its first argument; empty ignores
    commands.
  .PARAMETER ActivityRules
    Classification rules of the settings (objects with Pattern and Category), tried before the built-in ones.
  .PARAMETER Until
    Calls, human turns and rules after this instant are left out, so a profile can be recomputed for the period it
    first covered although the transcript grew afterwards.
  #>
  param([Parameter(Mandatory)][IO.FileInfo]$File, [int]$GapSeconds = 300, [Nullable[datetimeoffset]]$Until, [string[]]$WorkItemPatterns = @('^#(\d+)'), [string]$WorkItemCommandPattern = '', [object[]]$ActivityRules = @())
  $calls = [ordered]@{}
  $turns = New-Object System.Collections.Generic.List[object]
  $rules = New-Object System.Collections.Generic.List[object]
  $usageCalls = @{}; $readings = New-Object System.Collections.Generic.List[object]
  $curTurn = $null; $callN = 0; $version = ''; $branch = ''; $commandWorkItem = ''; $commitWorkItem = ''; $account = ''
  $askCalls = @{}; $firstHuman = $null; $lastAssistant = $null; $waitSpans = New-Object System.Collections.Generic.List[object]
  foreach ($line in [IO.File]::ReadLines($File.FullName)) {
    if ($line.Length -lt 20) { continue }
    if (-not $account -and $line -match '"organizationUuid":"([^"]+)"') { $account = Get-AccountLabel $Matches[1] }
    $o = $line | ConvertFrom-Json
    if ($o.isSidechain) { continue }
    if ($null -ne $Until -and $o.timestamp -and ([datetimeoffset]$o.timestamp) -gt $Until) { continue }
    if ($o.version) { $version = [string]$o.version }
    if ($o.gitBranch -and $o.gitBranch -ne 'HEAD') { $branch = [string]$o.gitBranch }
    if ($o.type -eq 'attachment') {
      $a = $o.attachment
      if ($a.type -eq 'nested_memory' -and $callN -gt 0) {
        $len = if ($a.content -and $a.content.content) { ([string]$a.content.content).Length } else { 0 }
        $rules.Add([pscustomobject]@{ Call = $callN; Name = ((Split-Path ([string]$a.path) -Leaf) -replace '\.md$', ''); Chars = $len })
      }
      continue
    }
    if ($o.type -eq 'user' -and $o.message) {
      $c = $o.message.content
      $isToolResult = $false
      if ($c -isnot [string]) {
        $results = @($c | Where-Object { $_.type -eq 'tool_result' })
        $isToolResult = $results.Count -gt 0
        foreach ($tr in $results) {
          $useId = [string]$tr.tool_use_id
          if ($askCalls.ContainsKey($useId)) { $waitSpans.Add(@($askCalls[$useId], [datetimeoffset]$o.timestamp)); $askCalls.Remove($useId) }
          if (-not $usageCalls.ContainsKey($useId)) { continue }
          $reading = Get-UsageReading $tr.content ([datetimeoffset]$o.timestamp)
          if ($reading) { $readings.Add($reading) }
        }
      }
      if (-not $isToolResult -and -not $o.isMeta -and -not $o.isCompactSummary -and (-not $o.origin -or $o.origin.kind -eq 'human')) {
        $txt = if ($c -is [string]) { $c } else { (@($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ') }
        $txt = ([string]$txt -replace '\s+', ' ').Trim()
        if ($txt.Length -gt 0 -and $txt -notmatch '^(<task-notification>|<local-command-std(out|err)>|\[Request interrupted)') {
          $time = [datetimeoffset]$o.timestamp
          if ($null -eq $firstHuman) { $firstHuman = $time }
          elseif ($null -ne $lastAssistant -and $lastAssistant -ge $firstHuman -and $time -gt $lastAssistant) { $waitSpans.Add(@($lastAssistant, $time)) }
          if (-not $commandWorkItem -and $WorkItemCommandPattern -and $txt -match "<command-name>(?:$WorkItemCommandPattern)</command-name>.*?<command-args>\s*#?([\w-]+)") { $commandWorkItem = $Matches[1] }
          $curTurn = [pscustomobject]@{ N = $turns.Count + 1; Time = [datetimeoffset]$o.timestamp; Text = $txt.Substring(0, [Math]::Min(90, $txt.Length)); Cost = 0.0; Calls = 0 }
          $turns.Add($curTurn)
        }
      }
      continue
    }
    if ($o.type -eq 'assistant') {
      $lastAssistant = [datetimeoffset]$o.timestamp
      foreach ($b in @($o.message.content)) {
        if ($b.type -ne 'tool_use') { continue }
        if ([string]$b.name -match '(^|__)get_usage$') { $usageCalls[[string]$b.id] = 1 }
        if ([string]$b.name -in 'AskUserQuestion', 'ExitPlanMode') { $askCalls[[string]$b.id] = $lastAssistant }
        if ($b.name -in 'Bash', 'PowerShell' -and [string]$b.input.command -match 'git\s+commit\b[\s\S]*?-m\s*(?:["''](\$\(cat\s+<<-?\s*[''"]?\w+[''"]?\s*\r?\n\s*)?|@["'']\s*\r?\n\s*)([^"''\r\n]*)') {
          # the first line of the message, also when it is passed as a here-document (-m "$(cat <<'EOF' ...) or as a PowerShell here-string (-m @'...)
          $found = Find-WorkItem $Matches[2] $WorkItemPatterns
          if ($found) { $commitWorkItem = $found }
        }
      }
    }
    if ($o.type -ne 'assistant' -or -not $o.message.usage) { continue }
    $key = "$($o.message.id)|$($o.requestId)"
    if (-not $calls.Contains($key)) {
      $u = Get-UsageTokens $o.message.usage
      $ctx = $u.In + $u.CR + $u.CW
      if ($ctx -gt 0) { $callN++ }
      $calls[$key] = [pscustomobject]@{
        Time = [datetimeoffset]$o.timestamp; Turn = $(if ($curTurn) { $curTurn.N } else { 0 }); U = $u; Ctx = $ctx
        Ttl = (Get-CacheLifetime $o.message.usage); Model = [string]$o.message.model; Tags = New-Object System.Collections.Generic.List[string]; Names = New-Object System.Collections.Generic.List[string]
      }
    }
    foreach ($b in @($o.message.content)) {
      if ($b.type -ne 'tool_use') { continue }
      $tag = [string]$b.name; $name = [string]$b.name
      # a command of the PowerShell tool is read like one of the Bash tool, so the rules for shell commands apply to both
      if ($b.name -in 'Bash', 'PowerShell') { $tag = 'Bash:' + [string]$b.input.command }
      elseif ($b.name -eq 'Agent') { $tag = 'Agent:' + [string]$b.input.subagent_type; $name = $tag }
      elseif ($b.name -eq 'Skill') { $tag = 'Skill:' + [string]$b.input.skill; $name = $tag }
      elseif ($b.name -in 'Write', 'Edit') { $tag = $b.name + ':' + [string]$b.input.file_path }
      $calls[$key].Tags.Add($tag); $calls[$key].Names.Add($name)
    }
  }

  # per-call rows of the main thread
  $rows = New-Object System.Collections.Generic.List[object]
  $prev = $null; $idx = 0; $ttl = $null
  foreach ($c in $calls.Values) {
    if ($c.Ctx -eq 0) { continue }
    $idx++
    $gap = if ($prev) { ($c.Time - $prev.Time).TotalSeconds } else { 0 }
    $lifetime = if ($null -ne $ttl) { $ttl } else { $GapSeconds }
    $r = [pscustomobject]@{
      I = $idx; Time = $c.Time; Turn = $c.Turn; Cat = (Get-ActivityCategory @($c.Tags) $ActivityRules); Names = (@($c.Names | Select-Object -Unique) -join ' + ')
      In = $c.U.In; Out = $c.U.Out; CR = $c.U.CR; CW = $c.U.CW; Ctx = $c.Ctx; Gap = $gap; Model = $c.Model
      Cost = (Get-CostUnits $c.U.In $c.U.CR $c.U.CW $c.U.Out)
      Rebuild = ($gap -gt $lifetime -and $c.U.CW -gt 30000)
      Compact = [bool]($prev -and $c.Ctx -lt 0.6 * $prev.Ctx -and $prev.Ctx -gt 50000)
    }
    if ($null -ne $c.Ttl) { $ttl = $c.Ttl }
    $rows.Add($r); $prev = $r
  }
  foreach ($r in $rows) { $t = $turns | Where-Object { $_.N -eq $r.Turn } | Select-Object -First 1; if ($t) { $t.Cost += $r.Cost; $t.Calls++ } }

  # carrying cost: tokens added after call i are re-read by every later call
  $n = $rows.Count; $carry = @{}; $carriers = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $n - 1; $i++) {
    $d = $rows[$i + 1].Ctx - $rows[$i].Ctx
    if ($d -le 0) { continue }
    $cc = $script:costWeights.CacheRead * $d * ($n - 1 - $i)
    $carry[$rows[$i].Cat] += $cc
    $carriers.Add([pscustomobject]@{ I = $rows[$i].I; Added = $d; Carry = $cc; Names = $(if ($rows[$i].Names) { $rows[$i].Names } else { '(reply)' }) })
  }
  foreach ($e in $rules) { $e | Add-Member Tok (Get-Tok $e.Chars); $e | Add-Member Carry ($script:costWeights.CacheRead * (Get-Tok $e.Chars) * [Math]::Max(0, $n - $e.Call)) }

  $models = @($rows | Group-Object Model | Sort-Object Count -Descending)
  [pscustomobject]@{
    Id = $File.BaseName; Version = $version; Branch = $branch; CommandWorkItem = $commandWorkItem; CommitWorkItem = $commitWorkItem; Account = $account
    Model = $(if ($models.Count) { $models[0].Name } else { '' })
    CacheTtl = $(if ($ttl -eq 3600) { '1h' } elseif ($ttl -eq 300) { '5m' } else { '' })
    Rows = $rows.ToArray(); Turns = $turns.ToArray(); Rules = $rules.ToArray(); CarryByCat = $carry; Carriers = $carriers.ToArray()
    UsageReadings = @($readings | Sort-Object Time)
    Duration = (Get-SessionDuration $firstHuman $(if ($rows.Count) { $rows[-1].Time } else { $null }) $waitSpans)
    Subagents = @(Read-SubagentTranscripts (Join-Path $File.DirectoryName (Join-Path $File.BaseName 'subagents')) $Until)
  }
}

function Get-SessionDuration {
  <#
  .SYNOPSIS
    Wall time from the first human turn to the last main-thread call, the part of it spent waiting for the user,
    and the number of waits; $null without a human turn before the last call.
  .DESCRIPTION
    The window ends at the last call rather than at the last line, so a recompute cut at the end of the stored
    period gives the same figures; a wait is clipped to the window, one entirely outside it is not counted, and overlapping waits count once.
  .PARAMETER Spans
    Start and end of each wait for the user.
  #>
  param($Start, $End, [object[]]$Spans)
  if ($null -eq $Start -or $null -eq $End -or $End -le $Start) { return $null }
  # waits can overlap (a message typed while a question is still open), and overlapping time counts once
  $clipped = New-Object System.Collections.Generic.List[object]
  foreach ($s in $Spans) {
    $a = if ($s[0] -lt $Start) { $Start } else { $s[0] }; $b = if ($s[1] -gt $End) { $End } else { $s[1] }
    if ($b -gt $a) { $clipped.Add(@($a, $b)) }
  }
  $waiting = 0.0; $waits = 0; $curEnd = $null
  $clipped.Sort([Comparison[object]]{ param($x, $y) $x[0].CompareTo($y[0]) })
  foreach ($s in $clipped) {
    if ($null -ne $curEnd -and $s[0] -le $curEnd) {
      if ($s[1] -gt $curEnd) { $waiting += ($s[1] - $curEnd).TotalSeconds; $curEnd = $s[1] }
    } else {
      $waiting += ($s[1] - $s[0]).TotalSeconds; $waits++; $curEnd = $s[1]
    }
  }
  [pscustomobject]@{ Wall = ($End - $Start).TotalSeconds; Waiting = $waiting; Waits = $waits }
}

function Get-PrefixMetrics {
  <#
  .SYNOPSIS
    Cost per call over the first N main-thread calls and the context of the N-th call; empty values when the
    session has fewer calls.
  .DESCRIPTION
    The cost of a call grows with the context it carries, and the context grows with the length of the session, so
    the average over a whole session is higher for a longer one. The same first N calls compare sessions of
    different length on an equal footing.
  #>
  param([object[]]$Rows, [int]$N)
  if ($Rows.Count -lt $N) { return [pscustomobject]@{ UnitsPerCall = ''; Ctx = '' } }
  $first = $Rows[0..($N - 1)]
  [pscustomobject]@{ UnitsPerCall = (($first | Measure-Object Cost -Sum).Sum / $N); Ctx = $Rows[$N - 1].Ctx }
}

function Get-LimitUsage {
  <#
  .SYNOPSIS
    Relates a session's cost to the weekly plan limit from the plan-usage readings in its transcript.
  .DESCRIPTION
    The start is the first reading and the end the last one. Used percent and units per 1 % are returned only when
    there are two readings or more, the weekly window is the same at both ends (reset times within an hour of each
    other), the end is not below the start and used percent is above 0; otherwise those two stay empty while the
    start and end readings are kept.

    Only the cost of the calls made between the two readings is related to the used percent: calls before the
    start spent limit that the start reading already contains, and calls after the end are not in the end reading.
  .PARAMETER Readings
    Plan-limit readings of the session in time order, as Read-WorkSession returns them.
  .PARAMETER Calls
    Time and cost of every model call of the session, main thread and subagents.
  #>
  param([object[]]$Readings, [object[]]$Calls)
  $res = [ordered]@{ WeeklyStartPct = ''; WeeklyStartAt = ''; WeeklyEndPct = ''; WeeklyUsedPct = ''; LimitCostUnits = ''; UnitsPerWeeklyPct = ''; Reason = 'no plan-usage reading in the session' }
  $readings = @($Readings | Where-Object { $_ })
  if (-not $readings.Count) { return [pscustomobject]$res }
  $start = $readings[0]
  $res.WeeklyStartPct = $start.WeeklyPct.ToString('0.##', $script:pinv)
  $res.WeeklyStartAt = $start.Time.UtcDateTime.ToString('yyyy-MM-dd HH:mm', $script:pinv)
  if ($readings.Count -lt 2) { $res.Reason = 'one plan-usage reading only, no end reading'; return [pscustomobject]$res }
  $end = $readings[-1]
  $res.WeeklyEndPct = $end.WeeklyPct.ToString('0.##', $script:pinv)
  $sr = ConvertTo-Instant $start.WeeklyResetsAt; $er = ConvertTo-Instant $end.WeeklyResetsAt
  if ($null -ne $sr -and $null -ne $er -and [Math]::Abs(($er - $sr).TotalMinutes) -gt 60) { $res.Reason = 'the weekly window rolled over between start and end'; return [pscustomobject]$res }
  $used = $end.WeeklyPct - $start.WeeklyPct
  if ($used -lt 0) { $res.Reason = 'the end reading is below the start reading'; return [pscustomobject]$res }
  if ($used -eq 0) { $res.Reason = 'no whole percent of the weekly limit was used'; return [pscustomobject]$res }
  $counted = @($Calls | Where-Object { $_.Time -ge $start.Time -and $_.Time -le $end.Time })
  $limitCost = [double](($counted | Measure-Object Cost -Sum).Sum)
  $res.WeeklyUsedPct = $used.ToString('0.##', $script:pinv)
  $res.LimitCostUnits = [Math]::Round($limitCost).ToString('0', $script:pinv)
  $res.UnitsPerWeeklyPct = [Math]::Round($limitCost / $used).ToString('0', $script:pinv)
  $res.Reason = ''
  [pscustomobject]$res
}

function ConvertTo-Instant {
  <#
  .SYNOPSIS
    Parses an ISO 8601 timestamp into a DateTimeOffset; returns $null for an empty or unreadable value.
  #>
  param($Value)
  if ($Value -is [datetime]) { return [datetimeoffset]$Value }
  if ($Value -is [datetimeoffset]) { return $Value }
  $s = [string]$Value
  if (-not $s) { return $null }
  $r = [datetimeoffset]::MinValue
  if ([datetimeoffset]::TryParse($s, $script:pinv, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$r)) { return $r }
  $null
}

function Resolve-BaseBranch {
  <#
  .SYNOPSIS
    Returns the branch a change is measured against: the configured one, else the branch origin/HEAD points to, else
    the first of develop, main and master that exists; empty when none does.
  .DESCRIPTION
    The branch of origin/HEAD is returned as its local branch when one exists, so that a session on that branch is
    recognised as a session on the base branch and gets no change size.
  #>
  param([string]$RepoRoot, [string]$Configured)
  $exists = { param($ref) & git -C $RepoRoot rev-parse --verify --quiet "$ref^{commit}" *> $null; $LASTEXITCODE -eq 0 }
  if ($Configured) { return $Configured }
  $head = [string]((& git -C $RepoRoot symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null) | Select-Object -First 1)
  if ($head) {
    $local = $head -replace '^origin/', ''
    if (& $exists "refs/heads/$local") { return $local }
    if (& $exists $head) { return $head }
  }
  foreach ($b in 'develop', 'main', 'master') { if (& $exists "refs/heads/$b") { return $b } }
  ''
}

function Get-DiffSize {
  <#
  .SYNOPSIS
    Files and lines (added plus removed) a branch changes against its merge base with the base branch.
  .DESCRIPTION
    For the branch that is checked out the working tree is compared, so uncommitted changes count as well. Returns
    empty values for the base branch itself, whose diff says nothing about the session, and for a branch that does
    not exist locally.
  #>
  param([string]$RepoRoot, [string]$Branch, [string]$BaseBranch)
  $res = [pscustomobject]@{ Files = ''; Lines = '' }
  if (-not $Branch -or -not $BaseBranch -or $Branch -eq $BaseBranch) { return $res }
  & git -C $RepoRoot rev-parse --verify --quiet "refs/heads/$Branch" *> $null
  if ($LASTEXITCODE -ne 0) { return $res }
  $base = (& git -C $RepoRoot merge-base $BaseBranch $Branch 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or -not $base) { return $res }
  $current = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
  $stat = if ($current -eq $Branch) { & git -C $RepoRoot diff --shortstat $base } else { & git -C $RepoRoot diff --shortstat $base $Branch }
  $s = [string]($stat | Select-Object -First 1)
  $files = if ($s -match '(\d+) files? changed') { [int]$Matches[1] } else { 0 }
  $ins = if ($s -match '(\d+) insertions?') { [int]$Matches[1] } else { 0 }
  $del = if ($s -match '(\d+) deletions?') { [int]$Matches[1] } else { 0 }
  $res.Files = "$files"; $res.Lines = "$($ins + $del)"
  $res
}

function Format-LimitRange {
  <#
  .SYNOPSIS
    Range of units per 1 % that whole-percent readings allow: "range a-b" or "at least a" for one percent used.
  .DESCRIPTION
    Both readings are whole numbers, so the percent really used lies between used - 1 and used + 1.
  #>
  param($LimitCostUnits, $UsedPct)
  $c = [double]$LimitCostUnits; $u = [double]$UsedPct
  if (-not $c -or -not $u) { return '' }
  $low = [Math]::Round($c / ($u + 1)).ToString('#,0', $script:pinv)
  if ($u -le 1) { return "at least $low from whole-percent rounding" }
  "range $low-$([Math]::Round($c / ($u - 1)).ToString('#,0', $script:pinv)) from whole-percent rounding"
}

function Format-Duration {
  <#
  .SYNOPSIS
    A number of seconds as hours and minutes ("2h 41m", "41m"), rounded to the minute.
  #>
  param($Seconds)
  $m = [int][Math]::Round([double]$Seconds / 60, [MidpointRounding]::AwayFromZero)
  if ($m -ge 60) { '{0}h {1:00}m' -f [Math]::Floor($m / 60), ($m % 60) } else { "${m}m" }
}

function Format-SessionProfile {
  <#
  .SYNOPSIS
    Console text of a parsed session: totals, token-type share, activities, subagents, context, carrying cost,
    rules loaded and the costliest human turns. Shown on screen only, never written to the repository.
  #>
  param($S, $Row, [int]$TopTurns = 8, $Limit)
  $f = { param($fmt) [string]::Format($script:pinv, $fmt, [object[]]$args) }
  $total = [double]$Row.CostUnits
  $pct = { param($x) if ($total) { ([double]$x / $total).ToString('0.0 %', $script:pinv) } else { '' } }
  $rows = $S.Rows; $subs = $S.Subagents
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("Session $($S.Id)")
  $lines.Add("Work item: $(if ($Row.WorkItem) { $Row.WorkItem } else { '(unknown)' })  lane: $(if ($Row.Lane) { $Row.Lane } else { '-' })  branch: $($Row.Branch)  commit: $($Row.Commit)")
  $lines.Add("Period: $($Row.Started) -> $($Row.Ended) UTC   Claude Code $($Row.Version), model $($Row.Model), account $(if ($Row.Account) { $Row.Account } else { '(unknown)' })")
  $lines.Add((& $f 'Main model calls: {0}   human turns: {1}   subagents: {2} ({3} calls)' $Row.Calls $Row.HumanTurns $Row.Subagents $Row.SubagentCalls))
  $d = $Row.Duration
  $lines.Add($(if ($d) { "Duration: $(Format-Duration $d.active) active of $(Format-Duration $d.wall) from the first human turn; $(Format-Duration $d.waiting) waiting for the user in $($d.waits) waits" } else { 'Duration: unknown (no human turn)' }))
  $lines.Add((& $f 'TOTAL weighted cost: {0:N0}   (main {1:N0} = {2}, subagents {3:N0} = {4})   units per main-thread call: {5:N0}' $total ([double]$Row.MainCost) (& $pct $Row.MainCost) ([double]$Row.SubagentCost) (& $pct $Row.SubagentCost) ([double]$Row.UnitsPerCall)))
  $prefix = @(foreach ($n in 40, 70) { $v = $Row."First${n}UnitsPerCall"; if ($v) { & $f 'first {0} calls {1:N0} per call (context at call {0}: {2:N0})' $n ([double]$v) ([double]$Row."First${n}Ctx") } })
  $lines.Add("Equal-length comparison: $(if ($prefix) { $prefix -join '; ' } else { 'session shorter than 40 calls' })")
  $lines.Add('')
  $lines.Add('== Token type share (main + subagents) ==')
  $w = $script:costWeights
  foreach ($p in @(@('cache read', $w.CacheRead, $Row.CacheReadTok), @('cache write', $w.CacheWrite, $Row.CacheWriteTok), @('output', $w.Output, $Row.OutTok), @('plain input', $w.Input, $Row.InputTok))) {
    $v = [double]$p[1] * [double]$p[2]
    $lines.Add((& $f '{0,-22} {1,14:N0}  {2}' "$($p[0]) (x$(Format-Weight $p[1]))" $v (& $pct $v)))
  }
  $lines.Add('')
  $lines.Add('== By activity (main-thread calls) ==')
  foreach ($g in ($rows | Group-Object Cat | ForEach-Object { [pscustomobject]@{ Cat = $_.Name; Calls = $_.Count; Cost = ($_.Group | Measure-Object Cost -Sum).Sum; AvgCtx = ($_.Group | Measure-Object Ctx -Average).Average } } | Sort-Object Cost -Descending)) {
    $lines.Add((& $f '{0,-24} calls={1,4}  cost={2,12:N0}  {3,7}  avg ctx={4,8:N0}  carry={5,11:N0}' $g.Cat $g.Calls $g.Cost (& $pct $g.Cost) $g.AvgCtx ([double]$S.CarryByCat[$g.Cat])))
  }
  $lines.Add('')
  $lines.Add('== Subagents by type and model ==')
  if (-not $subs.Count) { $lines.Add('none') }
  foreach ($g in (Get-SubagentsByModel $subs)) {
    $lines.Add((& $f '{0,-24} {1,-20} agents={2,3} calls={3,4}  cost={4,12:N0}  per call={5,8:N0}  {6}' $g.Type $g.Model $g.Agents $g.Calls $g.Cost ($g.Cost / $g.Calls) (& $pct $g.Cost)))
  }
  $lines.Add('')
  $lines.Add('== Context (input + cache read + cache write per main-thread call) ==')
  $lines.Add((& $f 'first {0:N0} | max {1:N0} | last {2:N0}' ([double]$Row.FirstCtx) ([double]$Row.MaxCtx) ([double]$Row.LastCtx)))
  $comp = @($rows | Where-Object Compact)
  $lines.Add("Compactions (context fell below 60 %): $($comp.Count)$(if ($comp.Count) { '  at calls ' + (($comp | ForEach-Object { $_.I }) -join ', ') })")
  $lines.Add((& $f 'Idle cache rebuilds (gap longer than the {0} cache lifetime, cache write > 30k): {1}, cost {2:N0} ({3})' $(if ($Row.CacheTtl) { $Row.CacheTtl } else { 'assumed 5m' }) $Row.IdleRebuilds ([double]$Row.IdleRebuildCost) (& $pct $Row.IdleRebuildCost)))
  $lines.Add((& $f 'Carrying cost of context growth: {0:N0}. Top carriers: {1}' ([double]$Row.CarryCost) $(if ($Row.TopCarriers) { $Row.TopCarriers } else { 'none' })))
  $lines.Add("Rules loaded during the session: $(if ($Row.RulesLoaded) { "$($Row.RulesLoaded) (~$($Row.RulesTok) tokens)" } else { 'none' })")
  if ($Limit) {
    $lines.Add('')
    if ($Limit.UnitsPerWeeklyPct) { $lines.Add((& $f 'Weekly limit: {0} % -> {1} % (used {2} %), {3:N0} units between the readings from {4} UTC, {5:N0} units per 1 % ({6})' $Limit.WeeklyStartPct $Limit.WeeklyEndPct $Limit.WeeklyUsedPct ([double]$Limit.LimitCostUnits) $Limit.WeeklyStartAt ([double]$Limit.UnitsPerWeeklyPct) (Format-LimitRange $Limit.LimitCostUnits $Limit.WeeklyUsedPct))) }
    else { $lines.Add("Weekly limit: not related ($($Limit.Reason))$(if ($Limit.WeeklyStartPct) { "; start $($Limit.WeeklyStartPct) %" })$(if ($Limit.WeeklyEndPct) { ", end $($Limit.WeeklyEndPct) %" })") }
  }
  $lines.Add('')
  $lines.Add("== Top $TopTurns costliest human turns (main thread, console only) ==")
  foreach ($t in ($S.Turns | Sort-Object Cost -Descending | Select-Object -First $TopTurns)) {
    $lines.Add((& $f '#{0,-3} {1:MM-dd HH:mm} calls={2,3} cost={3,10:N0} {4,7} | {5}' $t.N $t.Time.UtcDateTime $t.Calls $t.Cost (& $pct $t.Cost) $t.Text))
  }
  $lines
}
