# Price table refresh: reads the model prices from the Anthropic pricing page (Markdown), compares them with a price
# table and writes them to a settings file. The page is data only: nothing in it is run, only numbers are read.
. (Join-Path $PSScriptRoot 'Cost.ps1')

$script:pricingPageUrl = 'https://platform.claude.com/docs/en/about-claude/pricing.md'

function Split-MarkdownRow([string]$Line) {
  $t = $Line.Trim()
  if (-not $t.StartsWith('|')) { return $null }
  , @($t.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}

function Get-MarkdownTables {
  <#
  .SYNOPSIS
    Every pipe table of a Markdown text: its header cells and its body rows (lists of cells).
  #>
  param([string]$Text)
  $tables = New-Object System.Collections.Generic.List[object]
  $cur = $null
  foreach ($line in ($Text -split "`r?`n")) {
    $cells = Split-MarkdownRow $line
    if ($null -eq $cells) { $cur = $null; continue }
    if ($null -eq $cur) { $cur = [pscustomobject]@{ Header = $cells; Rows = New-Object System.Collections.Generic.List[object] }; $tables.Add($cur); continue }
    if (($cells -join '') -match '^[\s:\-]+$') { continue }
    $cur.Rows.Add($cells)
  }
  $tables
}

function ConvertTo-ModelId {
  <#
  .SYNOPSIS
    API model id of a model name of the pricing page: "Claude Opus 5.5" gives claude-opus-5-5. Notes in brackets
    and footnote marks are dropped. Returns '' for a name that is not "Claude <family> <version>".
  #>
  param([string]$Name)
  $n = ($Name -replace '<sup>.*?</sup>', '' -replace '\(.*\)', '').Trim()
  if ($n -notmatch '^Claude\s+([A-Za-z]+)\s+(\d+(?:\.\d+)?)$') { return '' }
  'claude-' + $Matches[1].ToLowerInvariant() + '-' + $Matches[2].Replace('.', '-')
}

function ConvertFrom-PriceCell([string]$Cell) {
  $c = $Cell -replace '<sup>.*?</sup>', ''
  if ($c -notmatch '\$\s*([0-9]+(?:\.[0-9]+)?)') { return $null }
  [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-PricingPage {
  <#
  .SYNOPSIS
    Reads the price table of every model from the Markdown of the Anthropic pricing page.
  .DESCRIPTION
    The model table is the one whose header names the base input, the 5m and 1h cache writes, the cache hits and the
    output. A row "(for prompts over N tokens)" gives the longPrompt prices of its model. The fast-mode table (header
    Model, Input, Output) gives fastMultiplier as fast input over base input; a row may name several models joined by
    " / ". Throws when the page has no model table, so a changed page format is not read as "no prices".
  .OUTPUTS
    An ordered table of model id to a price entry, as ConvertTo-ModelPrice returns it.
  #>
  param([Parameter(Mandatory)][string]$Text)
  $tables = @(Get-MarkdownTables $Text)
  $col = $null; $model = $null
  foreach ($t in $tables) {
    $h = @($t.Header | ForEach-Object { $_.ToLowerInvariant() })
    $find = { param($re) for ($i = 0; $i -lt $h.Count; $i++) { if ($h[$i] -match $re) { return $i } }; -1 }
    $c = [ordered]@{ input = (& $find '^base input'); cacheWrite5m = (& $find '^5m cache write'); cacheWrite1h = (& $find '^1h cache write'); cacheRead = (& $find '^cache hits'); output = (& $find '^output') }
    if ($h[0] -eq 'model' -and -not (@($c.Values) -contains -1)) { $col = $c; $model = $t; break }
  }
  if ($null -eq $model) { throw 'The pricing page has no model price table (Model, Base input tokens, 5m and 1h cache writes, Cache hits, Output tokens); its format may have changed. Update the price table by hand.' }
  $prices = [ordered]@{}
  foreach ($row in $model.Rows) {
    $id = ConvertTo-ModelId $row[0]
    if (-not $id) { continue }
    $p = [ordered]@{}
    foreach ($k in $script:priceKeys) { $p[$k] = ConvertFrom-PriceCell $row[$col[$k]] }
    if (@($p.Values) -contains $null) { continue }
    if ($row[0] -match 'prompts\s+over\s+([\d,]+)\s+tokens') {
      $above = [int64]($Matches[1] -replace ',', '')
      if ($prices.Contains($id)) { $l = [ordered]@{ above = $above }; foreach ($k in $script:priceKeys) { $l[$k] = $p[$k] }; $prices[$id].longPrompt = $l }
      continue
    }
    $prices[$id] = $p
  }
  if (-not $prices.Count) { throw 'The model price table of the pricing page has no row that could be read; its format may have changed. Update the price table by hand.' }
  foreach ($t in $tables) {
    $h = @($t.Header | ForEach-Object { $_.ToLowerInvariant() })
    if (($h -join '|') -ne 'model|input|output') { continue }
    foreach ($row in $t.Rows) {
      $fastIn = ConvertFrom-PriceCell $row[1]
      if ($null -eq $fastIn) { continue }
      foreach ($name in ($row[0] -split '\s+/\s+')) {
        $id = ConvertTo-ModelId $name
        if ($id -and $prices.Contains($id) -and $prices[$id].input -gt 0) { $prices[$id].fastMultiplier = [Math]::Round($fastIn / $prices[$id].input, 4) }
      }
    }
  }
  $prices
}

function Get-PriceText {
  <#
  .SYNOPSIS
    One-line JSON of a price entry in a fixed key order, as the defaults file writes it; also used to compare entries.
  #>
  param($Price)
  $num = { param($x) ([double]$x).ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }
  $parts = foreach ($k in $script:priceKeys) { "`"$k`": $(& $num $Price[$k])" }
  if ($Price.Contains('fastMultiplier')) { $parts = @($parts) + "`"fastMultiplier`": $(& $num $Price.fastMultiplier)" }
  if ($Price.Contains('longPrompt')) {
    $l = $Price.longPrompt
    $lp = @("`"above`": $($l.above)") + @(foreach ($k in $script:priceKeys) { "`"$k`": $(& $num $l[$k])" })
    $parts = @($parts) + "`"longPrompt`": { $($lp -join ', ') }"
  }
  '{ ' + ($parts -join ', ') + ' }'
}

function Compare-PriceTable {
  <#
  .SYNOPSIS
    Differences of a price table from the prices of the pricing page: models the page adds, models whose prices
    differ, and models of the table the page does not list (kept as they are).
  #>
  param($Current, $Page)
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($id in $Page.Keys) {
    $new = Get-PriceText $Page[$id]
    if (-not $Current.Contains($id)) { $out.Add([pscustomobject]@{ Model = $id; Change = 'added'; Old = ''; New = $new }); continue }
    $old = Get-PriceText $Current[$id]
    if ($old -ne $new) { $out.Add([pscustomobject]@{ Model = $id; Change = 'changed'; Old = $old; New = $new }) }
  }
  foreach ($id in $Current.Keys) { if (-not $Page.Contains($id)) { $out.Add([pscustomobject]@{ Model = $id; Change = 'not on the page'; Old = (Get-PriceText $Current[$id]); New = '' }) } }
  $out
}

function Format-PricesBlock {
  <#
  .SYNOPSIS
    The "pricesUpdated" and "prices" keys as JSON text, one model per line, indented by two spaces.
  #>
  param([string]$Date, $Prices)
  $lines = @(foreach ($id in $Prices.Keys) { "    `"$id`": $(Get-PriceText $Prices[$id])" })
  "  `"pricesUpdated`": `"$Date`",`n  `"prices`": {`n" + ($lines -join ",`n") + $(if ($lines.Count) { "`n" } else { '' }) + '  }'
}

function Write-PricesToSettings {
  <#
  .SYNOPSIS
    Writes pricesUpdated and prices into a settings file and keeps its other keys; creates the file when it is missing.
  .DESCRIPTION
    The other keys are written back as JSON in their order, the prices one model per line after them. The file is
    UTF-8 without BOM with LF line ends.
  #>
  param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Date, [Parameter(Mandatory)]$Prices)
  $other = [ordered]@{}
  if (Test-Path $File) {
    $cfg = [IO.File]::ReadAllText($File) | ConvertFrom-Json
    foreach ($p in $cfg.PSObject.Properties) { if ($p.Name -notin 'prices', 'pricesUpdated') { $other[$p.Name] = $p.Value } }
  }
  $body = @(foreach ($k in $other.Keys) {
      $v = ($other[$k] | ConvertTo-Json -Depth 8 -Compress)
      if ($other[$k] -is [string]) { $v = ConvertTo-Json $other[$k] }
      "  `"$k`": $v"
    })
  $text = "{`n" + ((@($body) + (Format-PricesBlock $Date $Prices)) -join ",`n") + "`n}`n"
  # a file whose price keys come last keeps the text of its other keys as it is (for example the defaults file)
  if (Test-Path $File) {
    $old = [IO.File]::ReadAllText($File) -replace "`r`n", "`n"
    $i = $old.IndexOf("`n  `"pricesUpdated`"")
    if ($i -gt 0) {
      $head = $old.Substring(0, $i).TrimEnd().TrimEnd(',')
      $candidate = "$head,`n$(Format-PricesBlock $Date $Prices)`n}`n"
      try {
        $c = $candidate | ConvertFrom-Json
        $keys = { param($o) ($o.PSObject.Properties | Where-Object { $_.Name -notin 'prices', 'pricesUpdated' } | ForEach-Object { $_.Name + '=' + ($_.Value | ConvertTo-Json -Depth 8 -Compress) }) -join ';' }
        if ((& $keys $c) -eq (& $keys $cfg)) { $text = $candidate }
      } catch { }
    }
  }
  $null = $text | ConvertFrom-Json
  $dir = Split-Path $File -Parent
  if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($File, $text, [Text.UTF8Encoding]::new($false))
}
