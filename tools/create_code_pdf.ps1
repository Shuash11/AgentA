param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Title = "Code Listing"
)

$ErrorActionPreference = "Stop"

function Escape-PdfText {
    param([string]$Text)
    return ($Text -replace "\\", "\\" -replace "\(", "\(" -replace "\)", "\)")
}

function Wrap-Line {
    param(
        [string]$Line,
        [int]$Width
    )

    if ($Line.Length -le $Width) {
        return @($Line)
    }

    $wrapped = New-Object System.Collections.Generic.List[string]
    $remaining = $Line
    while ($remaining.Length -gt $Width) {
        $wrapped.Add($remaining.Substring(0, $Width))
        $remaining = "    " + $remaining.Substring($Width)
    }
    $wrapped.Add($remaining)
    return $wrapped.ToArray()
}

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$rawLines = Get-Content -LiteralPath $source
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($Title)
$lines.Add($source)
$lines.Add("")
foreach ($line in $rawLines) {
    foreach ($wrapped in (Wrap-Line -Line $line -Width 94)) {
        $lines.Add($wrapped)
    }
}

$linesPerPage = 58
$pageCount = [Math]::Ceiling($lines.Count / $linesPerPage)
$objects = New-Object System.Collections.Generic.List[string]

$objects.Add("<< /Type /Catalog /Pages 2 0 R >>")

$kids = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $pageCount; $i++) {
    $pageObjNum = 4 + ($i * 2)
    $kids.Add("$pageObjNum 0 R")
}
$objects.Add("<< /Type /Pages /Kids [ $($kids -join ' ') ] /Count $pageCount >>")
$objects.Add("<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>")

for ($page = 0; $page -lt $pageCount; $page++) {
    $pageObjNum = 4 + ($page * 2)
    $contentObjNum = $pageObjNum + 1
    $start = $page * $linesPerPage
    $end = [Math]::Min($start + $linesPerPage, $lines.Count)

    $content = New-Object System.Text.StringBuilder
    [void]$content.AppendLine("BT")
    [void]$content.AppendLine("/F1 8 Tf")
    [void]$content.AppendLine("40 760 Td")
    [void]$content.AppendLine("10 TL")

    for ($i = $start; $i -lt $end; $i++) {
        $escaped = Escape-PdfText $lines[$i]
        [void]$content.AppendLine("($escaped) Tj")
        [void]$content.AppendLine("T*")
    }

    [void]$content.AppendLine("ET")
    $contentString = $content.ToString()
    $length = ([System.Text.Encoding]::ASCII.GetBytes($contentString)).Length

    $objects.Add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObjNum 0 R >>")
    $objects.Add("<< /Length $length >>`nstream`n$contentString`nendstream")
}

$pdf = New-Object System.Text.StringBuilder
[void]$pdf.AppendLine("%PDF-1.4")
$offsets = New-Object System.Collections.Generic.List[int]
$ascii = [System.Text.Encoding]::ASCII

for ($i = 0; $i -lt $objects.Count; $i++) {
    $offsets.Add($ascii.GetByteCount($pdf.ToString()))
    [void]$pdf.AppendLine("$($i + 1) 0 obj")
    [void]$pdf.AppendLine($objects[$i])
    [void]$pdf.AppendLine("endobj")
}

$xrefOffset = $ascii.GetByteCount($pdf.ToString())
[void]$pdf.AppendLine("xref")
[void]$pdf.AppendLine("0 $($objects.Count + 1)")
[void]$pdf.AppendLine("0000000000 65535 f ")
foreach ($offset in $offsets) {
    [void]$pdf.AppendLine(("{0:0000000000} 00000 n " -f $offset))
}
[void]$pdf.AppendLine("trailer")
[void]$pdf.AppendLine("<< /Size $($objects.Count + 1) /Root 1 0 R >>")
[void]$pdf.AppendLine("startxref")
[void]$pdf.AppendLine("$xrefOffset")
[void]$pdf.AppendLine("%%EOF")

[System.IO.File]::WriteAllBytes($OutputPath, $ascii.GetBytes($pdf.ToString()))
Write-Host "Created PDF: $OutputPath"
