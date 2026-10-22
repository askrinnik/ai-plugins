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
