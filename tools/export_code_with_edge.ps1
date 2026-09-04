param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Title = "Code Listing"
)

$ErrorActionPreference = "Stop"

$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path -LiteralPath $edge)) {
    $edge = "C:\Program Files\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path -LiteralPath $edge)) {
    throw "Neither Edge nor Chrome was found."
}

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outDir = Split-Path -Parent $output
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$code = [System.Net.WebUtility]::HtmlEncode((Get-Content -LiteralPath $source -Raw))
$safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
$safeSource = [System.Net.WebUtility]::HtmlEncode($source)
$htmlPath = [System.IO.Path]::ChangeExtension($output, ".html")
$userDataDir = Join-Path $outDir "edge_pdf_profile"

$html = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>$safeTitle</title>
  <style>
    @page { size: A4; margin: 14mm; }
    body {
      font-family: "Segoe UI", Arial, sans-serif;
      color: #111827;
      background: #ffffff;
      margin: 0;
    }
    h1 {
      font-size: 20px;
      margin: 0 0 4px;
      color: #0D2137;
    }
    .path {
      font-size: 10px;
      color: #475569;
      margin-bottom: 14px;
    }
    pre {
      font-family: Consolas, "Courier New", monospace;
      font-size: 8.5px;
      line-height: 1.32;
      white-space: pre-wrap;
      word-break: break-word;
      margin: 0;
      padding: 12px;
      background: #f8fafc;
      border-left: 4px solid #1A6B8A;
    }
  </style>
</head>
<body>
  <h1>$safeTitle</h1>
  <div class="path">$safeSource</div>
  <pre>$code</pre>
</body>
</html>
"@

Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Force
}
if (Test-Path -LiteralPath $userDataDir) {
    Remove-Item -LiteralPath $userDataDir -Recurse -Force
}
New-Item -ItemType Directory -Path $userDataDir | Out-Null

$fileUrl = "file:///" + ($htmlPath -replace "\\", "/")
& $edge --headless --disable-gpu --no-sandbox "--user-data-dir=$userDataDir" "--print-to-pdf=$output" $fileUrl | Out-Null

if (-not (Test-Path -LiteralPath $output)) {
    throw "PDF was not created: $output"
}

Write-Host "Exported PDF: $output"
