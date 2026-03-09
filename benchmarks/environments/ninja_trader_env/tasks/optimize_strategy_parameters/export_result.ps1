$ErrorActionPreference = "Continue"

Write-Host "=== Exporting optimize_strategy_parameters result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$expectedOutput = Join-Path $outputDir "msft_optimization_results.csv"

# Check if the expected output file exists
$fileExists = Test-Path $expectedOutput
$fileSize = 0
$lineCount = 0
$hasMSFT = $false
$hasMultipleRows = $false
$hasPerformanceMetrics = $false
$hasParameterVariation = $false
$headerLine = ""
$sampleLines = @()

if ($fileExists) {
    $fileInfo = Get-Item $expectedOutput
    $fileSize = $fileInfo.Length

    try {
        $lines = Get-Content $expectedOutput -ErrorAction SilentlyContinue
        $lineCount = $lines.Count

        if ($lineCount -gt 0) {
            $headerLine = $lines[0]
            $sampleLines = $lines | Select-Object -First 10

            $fullContent = $lines -join "`n"
            $contentLower = $fullContent.ToLower()

            if ($contentLower -match "msft") { $hasMSFT = $true }

            # Multiple data rows (excluding header) indicate optimization ran
            if ($lineCount -gt 3) { $hasMultipleRows = $true }

            # Check for performance metrics
            if ($contentLower -match "profit|drawdown|return|net|pnl|trades|win|loss") {
                $hasPerformanceMetrics = $true
            }

            # Check for parameter variation (different numbers suggesting different params)
            $numberMatches = [regex]::Matches($fullContent, "\b(5|10|15|20|30|40|50|60)\b")
            $uniqueNumbers = $numberMatches | ForEach-Object { $_.Value } | Sort-Object -Unique
            if ($uniqueNumbers.Count -ge 3) {
                $hasParameterVariation = $true
            }
        }
    } catch {
        Write-Host "WARNING: Could not read export file: $($_.Exception.Message)"
    }
}

# Check for alternative export locations
$altPaths = @(
    "C:\Users\Docker\Desktop\msft_optimization_results.csv",
    "C:\Users\Docker\Documents\msft_optimization_results.csv",
    "C:\Users\Docker\Desktop\NinjaTraderTasks\msft_optimization_results.txt"
)
$altFileFound = $false
$altFilePath = ""
foreach ($alt in $altPaths) {
    if (Test-Path $alt) {
        $altFileFound = $true
        $altFilePath = $alt
        break
    }
}

# Create result JSON
$result = @{
    file_exists = $fileExists
    file_size = $fileSize
    line_count = $lineCount
    has_msft = $hasMSFT
    has_multiple_rows = $hasMultipleRows
    has_performance_metrics = $hasPerformanceMetrics
    has_parameter_variation = $hasParameterVariation
    header_line = $headerLine
    sample_lines = ($sampleLines -join "`n")
    alt_file_found = $altFileFound
    alt_file_path = $altFilePath
    export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "optimize_strategy_parameters_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
