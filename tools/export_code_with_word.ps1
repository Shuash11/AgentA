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

$word = $null
$doc = $null

try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $doc = $word.Documents.Add()

    $doc.PageSetup.TopMargin = 36
    $doc.PageSetup.BottomMargin = 36
    $doc.PageSetup.LeftMargin = 36
    $doc.PageSetup.RightMargin = 36

    $selection = $word.Selection
    $selection.Font.Name = "Aptos Display"
    $selection.Font.Size = 16
    $selection.Font.Bold = $true
    $selection.TypeText($Title)
    $selection.TypeParagraph()

    $selection.Font.Name = "Aptos"
    $selection.Font.Size = 9
    $selection.Font.Bold = $false
    $selection.TypeText($source)
    $selection.TypeParagraph()
    $selection.TypeParagraph()

    $selection.Font.Name = "Consolas"
    $selection.Font.Size = 7.5
    $selection.Font.Bold = $false

    $lineNumber = 1
    foreach ($line in Get-Content -LiteralPath $source) {
        $selection.TypeText(("{0,4}: {1}" -f $lineNumber, $line))
        $selection.TypeParagraph()
        $lineNumber++
    }

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
