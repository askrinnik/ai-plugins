<#
.SYNOPSIS
  Exports a .docx to PDF with Microsoft Word and keeps the hyperlinks.

.DESCRIPTION
  Run in pwsh (PowerShell 7). Word's SaveAs/Export hangs in a hidden instance under Windows PowerShell 5.1.

    pwsh -File scripts\export-pdf.ps1 -Docx <file.docx>

  Writes <file>.pdf next to the .docx (an existing PDF is overwritten) and prints the page count and the links
  found in the PDF. "Microsoft Print to PDF" drops every hyperlink, so do not use it for CVs.
#>
param(
  [Parameter(Mandatory = $true)][string]$Docx
)
$ErrorActionPreference = 'Stop'

$docxPath = (Resolve-Path -LiteralPath $Docx).Path
$pdfPath = [IO.Path]::ChangeExtension($docxPath, '.pdf')

$word = New-Object -ComObject Word.Application
$word.Visible = $false
try {
  $doc = $word.Documents.Open($docxPath, $false, $true)   # ConfirmConversions=false, ReadOnly=true
  try {
    $pages = $doc.ComputeStatistics(2)                      # wdStatisticPages
    # 17 = wdExportFormatPDF; CreateBookmarks/DocStructureTags keep the document navigable.
    $doc.ExportAsFixedFormat($pdfPath, 17, $false, 0, 0, 1, 1, 0, $true, $true, 1, $true, $true, $false)
  }
  finally {
    $doc.Close($false)
  }
}
finally {
  $word.Quit()
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}

$raw = [IO.File]::ReadAllText($pdfPath, [Text.Encoding]::GetEncoding(28591))
$links = [regex]::Matches($raw, '/URI\s*\(([^)]*)\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
Write-Output "PDF: $pdfPath"
Write-Output "Pages: $pages"
Write-Output "Links: $(@($links).Count)"
$links | ForEach-Object { Write-Output "  $_" }
