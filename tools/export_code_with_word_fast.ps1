param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Title = "Code Listing"
)

$ErrorActionPreference = "Stop"

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outDir = Split-Path -Parent $output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$code = Get-Content -LiteralPath $source -Raw
$content = "$Title`r`n$source`r`n`r`n$code"

$word = $null
$doc = $null

try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0

    $doc = $word.Documents.Add()
    $doc.PageSetup.TopMargin = 36
    $doc.PageSetup.BottomMargin = 36
    $doc.PageSetup.LeftMargin = 36
    $doc.PageSetup.RightMargin = 36

    $range = $doc.Range()
    $range.Text = $content
    $range.Font.Name = "Consolas"
    $range.Font.Size = 7.5

    $titleRange = $doc.Range(0, $Title.Length)
    $titleRange.Font.Name = "Aptos Display"
    $titleRange.Font.Size = 16
    $titleRange.Font.Bold = $true
    $titleRange.Font.Color = 3613453

    $doc.ExportAsFixedFormat($output, 17)
}
finally {
    if ($doc -ne $null) {
        $doc.Close($false)
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
    }
    if ($word -ne $null) {
        $word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

Write-Host "Exported PDF: $output"
