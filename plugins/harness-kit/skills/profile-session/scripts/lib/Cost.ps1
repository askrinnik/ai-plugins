# Cost model of a model call: relative price of one token of each kind, with new input as 1, and the helpers that
# turn token counts into cost units and into estimated tokens.
$script:tokPerChar = 1 / 3.76

function Get-Tok($chars) { [int]([double]$chars * $script:tokPerChar) }

# weights are written with a decimal point whatever the culture, so records read the same everywhere
function Format-Weight($w) { ([double]$w).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) }

function Get-CostUnits($inTok, $cacheRead, $cacheWrite, $outTok) {
  $w = $script:costWeights
  $inTok * $w.Input + $cacheRead * $w.CacheRead + $cacheWrite * $w.CacheWrite + $outTok * $w.Output
}

function Set-CostWeights {
  <#
  .SYNOPSIS
    Sets the weights of the cost model from an object with input, cacheRead, cacheWrite and output.
  .DESCRIPTION
    Each weight must be a number of zero or more; a missing key keeps its current value, so an object with only
    some of the keys changes only those.
  #>
  param([Parameter(Mandatory)]$Weights)
  $names = [ordered]@{ input = 'Input'; cacheRead = 'CacheRead'; cacheWrite = 'CacheWrite'; output = 'Output' }
  foreach ($p in $Weights.PSObject.Properties) {
    if (-not $names.Contains($p.Name)) { throw "Unknown cost weight '$($p.Name)'; the weights are input, cacheRead, cacheWrite and output." }
  }
  foreach ($k in $names.Keys) {
    $v = $Weights.$k
    if ($null -eq $v) { continue }
    $d = 0.0
    if (-not [double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -or $d -lt 0) {
      throw "Cost weight '$k' must be a number of zero or more, not '$v'."
    }
    $script:costWeights[$names[$k]] = $d
  }
}

function Copy-CostWeights {
  <#
  .SYNOPSIS
    Returns an independent copy of a weights table, so a table can be set aside and restored.
  #>
  param([Parameter(Mandatory)]$Weights)
  $copy = [ordered]@{}
  foreach ($k in $Weights.Keys) { $copy[$k] = $Weights[$k] }
  $copy
}

function Reset-CostWeights {
  <#
  .SYNOPSIS
    Sets the weights of the cost model to the built-in values.
  #>
  $script:costWeights = [ordered]@{ Input = 1; CacheRead = 0.1; CacheWrite = 1.25; Output = 5 }
}

Reset-CostWeights

# ---- estimated cost in USD at API list prices: a price table of USD per 1M tokens per model id

$script:priceKeys = 'input', 'output', 'cacheWrite5m', 'cacheWrite1h', 'cacheRead'

function ConvertTo-PriceNumber($Value, [string]$What, [switch]$Positive) {
  $d = 0.0
  if ($null -eq $Value -or $Value -is [bool] -or -not [double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -or $d -lt 0 -or ($Positive -and $d -eq 0)) {
    throw "$What must be a number of $(if ($Positive) { 'more than zero' } else { 'zero or more' }), not '$Value'."
  }
  $d
}

function ConvertTo-ModelPrice {
  <#
  .SYNOPSIS
    Checks one model entry of the price table and returns it as an ordered table.
  .DESCRIPTION
    An entry needs the five prices (input, output, cacheWrite5m, cacheWrite1h, cacheRead) in USD per 1M tokens.
    Optional: fastMultiplier, the factor of fast mode on every price, and longPrompt, a second set of the five prices
    with "above", the prompt size in tokens (input + cache read + cache write) over which a request pays them.
  #>
  param([Parameter(Mandatory)][string]$Model, $Entry)
  if ($Entry -isnot [pscustomobject] -and $Entry -isnot [Collections.IDictionary]) { throw "Price of '$Model' must be an object." }
  $props = if ($Entry -is [Collections.IDictionary]) { @($Entry.Keys) } else { @($Entry.PSObject.Properties.Name) }
  foreach ($n in $props) {
    if ($n -notin ($script:priceKeys + 'fastMultiplier', 'longPrompt')) { throw "Unknown price key '$n' of '$Model'; the keys are $($script:priceKeys -join ', '), fastMultiplier and longPrompt." }
  }
  $out = [ordered]@{}
  foreach ($k in $script:priceKeys) { $out[$k] = ConvertTo-PriceNumber $Entry.$k "Price '$k' of '$Model'" }
  if ($props -contains 'fastMultiplier') { $out.fastMultiplier = ConvertTo-PriceNumber $Entry.fastMultiplier "fastMultiplier of '$Model'" -Positive }
  if ($props -contains 'longPrompt') {
    $lp = $Entry.longPrompt
    if ($lp -isnot [pscustomobject] -and $lp -isnot [Collections.IDictionary]) { throw "longPrompt of '$Model' must be an object." }
    $l = [ordered]@{ above = [int64](ConvertTo-PriceNumber $lp.above "longPrompt.above of '$Model'" -Positive) }
    foreach ($k in $script:priceKeys) { $l[$k] = ConvertTo-PriceNumber $lp.$k "Price 'longPrompt.$k' of '$Model'" }
    $out.longPrompt = $l
  }
  $out
}

function Set-ModelPrices {
  <#
  .SYNOPSIS
    Adds or replaces model entries of the price table from an object keyed by model id; an entry replaces the
    earlier entry of that model as a whole.
  #>
  param([Parameter(Mandatory)]$Prices)
  $props = if ($Prices -is [Collections.IDictionary]) { @($Prices.Keys) } else { @($Prices.PSObject.Properties.Name) }
  foreach ($m in $props) { $script:modelPrices[$m] = ConvertTo-ModelPrice $m $Prices.$m }
}

function Reset-ModelPrices {
  <#
  .SYNOPSIS
    Empties the price table; the settings files fill it.
  #>
  $script:modelPrices = [ordered]@{}
  $script:pricesUpdated = ''
}

function Get-ModelPrice {
  <#
  .SYNOPSIS
    Price entry of a model id, or $null when the table has none. A dated snapshot id (claude-x-4-5-20251001) takes
    the entry of its id without the date when the table has no entry for the snapshot itself.
  #>
  param([string]$Model)
  if (-not $Model) { return $null }
  if ($script:modelPrices.Contains($Model)) { return $script:modelPrices[$Model] }
  $base = $Model -replace '-\d{8}$', ''
  if ($base -ne $Model -and $script:modelPrices.Contains($base)) { return $script:modelPrices[$base] }
  $null
}

function Get-CallUsd {
  <#
  .SYNOPSIS
    Estimated USD of one model call at the list prices of its model; $null when the table has no price for it.
  .DESCRIPTION
    Cache writes are split by lifetime from usage.cache_creation; without the split, or for the part it does not
    cover, a write is priced as a five-minute write. A call in fast mode (usage.speed "fast") is priced with the
    fastMultiplier of its model and has no price without one. A request whose prompt is over longPrompt.above tokens
    pays the longPrompt prices.
  .OUTPUTS
    An object with Usd (a number or $null) and Unpriced (the model id, with " (fast)" for fast mode, or '').
  #>
  param([string]$Model, $Usage)
  $p = Get-ModelPrice $Model
  $fast = [string]$Usage.speed -eq 'fast'
  if ($null -eq $p) { return [pscustomobject]@{ Usd = $null; Unpriced = $Model } }
  if ($fast -and -not $p.Contains('fastMultiplier')) { return [pscustomobject]@{ Usd = $null; Unpriced = "$Model (fast)" } }
  $in = [double]$Usage.input_tokens; $out = [double]$Usage.output_tokens
  $cr = [double]$Usage.cache_read_input_tokens; $cw = [double]$Usage.cache_creation_input_tokens
  $cw1h = 0.0
  if ($Usage.cache_creation) { $cw1h = [Math]::Min($cw, [double]$Usage.cache_creation.ephemeral_1h_input_tokens) }
  $cw5m = $cw - $cw1h
  $t = $p
  if ($p.Contains('longPrompt') -and ($in + $cr + $cw) -gt $p.longPrompt.above) { $t = $p.longPrompt }
  $usd = ($in * $t.input + $out * $t.output + $cw5m * $t.cacheWrite5m + $cw1h * $t.cacheWrite1h + $cr * $t.cacheRead) / 1e6
  if ($fast) { $usd *= $p.fastMultiplier }
  [pscustomobject]@{ Usd = $usd; Unpriced = '' }
}

function Get-UsdSum {
  <#
  .SYNOPSIS
    Sum of the Usd property of the given items; $null when one of them has none.
  #>
  param([object[]]$Items)
  $sum = 0.0
  foreach ($i in $Items) { if ($null -eq $i.Usd) { return $null }; $sum += [double]$i.Usd }
  $sum
}

Reset-ModelPrices
