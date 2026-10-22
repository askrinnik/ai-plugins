# Builds report.html from the session records: one self-contained page (data, CSS and JavaScript inline, no
# external resource) rebuilt whole on every run, so it always matches the records.

function Write-SessionReport {
  <#
  .SYNOPSIS
    Writes the HTML report of every record in a folder and returns the path of the written file.
  .DESCRIPTION
    The records are embedded as one JSON array in a script element of the page template report.html next to this
    file. Each record is parsed first, so a damaged file stops the build instead of breaking the page; "</" is
    written as "<\/", which is the same JSON string and cannot close the script element.
  .PARAMETER RecordsDir
    Folder of the <date>_<session>.json records.
  .PARAMETER File
    Path of the report to write.
  #>
  param([Parameter(Mandatory)][string]$RecordsDir, [Parameter(Mandatory)][string]$File)
  $texts = foreach ($f in (Get-ChildItem $RecordsDir -File -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $t = [IO.File]::ReadAllText($f.FullName).Trim()
    try { $null = $t | ConvertFrom-Json } catch { throw "Record $($f.Name) is not valid JSON: $($_.Exception.Message)" }
    $t
  }
  $json = ('[' + (@($texts) -join ",`n") + ']').Replace('</', '<\/')
  $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'report.html'))
  $placeholder = '/*SESSION_DATA*/'
  if (-not $template.Contains($placeholder)) { throw "The report template has no $placeholder placeholder." }
  New-Item -ItemType Directory -Force (Split-Path $File -Parent) | Out-Null
  [IO.File]::WriteAllText($File, $template.Replace($placeholder, $json), [Text.UTF8Encoding]::new($false))
  $File
}
