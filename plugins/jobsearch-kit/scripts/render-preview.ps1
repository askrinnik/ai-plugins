<#
.SYNOPSIS
  Renders a .docx to PDF (Microsoft Word) and to one PNG per page, so the layout can be inspected.

.DESCRIPTION
  Run under PowerShell 7 (pwsh, the PowerShell tool's default host):

    scripts\render-preview.ps1 -Docx <file.docx> [-OutDir <dir>] [-Width 1000]

  The Word step must run in pwsh: from Windows PowerShell 5.1, Word's SaveAs2 hangs in a hidden
  instance. The PDF-to-PNG step needs the WinRT Windows.Data.Pdf API, which pwsh cannot load, so this
  script hands it to pdf-to-png.ps1 under powershell.exe.

  Output: <OutDir>\preview.pdf and <OutDir>\page1.png, page2.png, ... (old page*.png are removed).
#>
param(
  [Parameter(Mandatory = $true)][string]$Docx,
  [string]$OutDir = (Join-Path $env:TEMP 'jobsearch\preview'),
  [int]$Width = 1000
)
$ErrorActionPreference = 'Stop'

$Docx = (Resolve-Path $Docx).Path
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$pdfPath = Join-Path $OutDir 'preview.pdf'
Get-ChildItem $OutDir -Filter 'page*.png' | Remove-Item -Force
Remove-Item $pdfPath -ErrorAction SilentlyContinue

# Word opens the file read-only, so a document the user has open in Word is not touched.
$word = New-Object -ComObject Word.Application
try {
  $word.Visible = $false
  $doc = $word.Documents.Open($Docx, $false, $true)
  Write-Output ("Word pages: " + $doc.ComputeStatistics(2))
  $doc.SaveAs2($pdfPath, 17) # wdFormatPDF
  $doc.Close($false)
}
finally {
  $word.Quit()
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pdf-to-png.ps1') -Pdf $pdfPath -OutDir $OutDir -Width $Width
if ($LASTEXITCODE -ne 0) { throw "pdf-to-png.ps1 failed with exit code $LASTEXITCODE" }
