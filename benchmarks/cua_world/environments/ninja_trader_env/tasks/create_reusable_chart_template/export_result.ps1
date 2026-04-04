$ErrorActionPreference = "Continue"

Write-Host "=== Exporting create_reusable_chart_template result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$ntDocDir = "C:\Users\Docker\Documents\NinjaTrader 8"
$templateDir = Join-Path $ntDocDir "templates\Chart"
$wsDir = Join-Path $ntDocDir "workspaces"

# Read baseline
$baselinePath = Join-Path $outputDir "chart_template_baseline.json"
$baseline = @{ existing_templates = @() }
if (Test-Path $baselinePath) {
    try {
        $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    } catch { }
}

# Check for SwingTrading template
$templateFound = $false
$templatePath = ""
$templateSize = 0
$templateContent = ""
$hasEMA = $false
$hasRSI = $false
$hasMACD = $false
$emaCount = 0

if (Test-Path $templateDir) {
    # Look for SwingTrading template (case-insensitive, with or without extension)
    $templates = Get-ChildItem $templateDir -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)SwingTrading|swing.?trading"
    }

    if ($templates) {
        $template = $templates | Select-Object -First 1
        $templateFound = $true
        $templatePath = $template.FullName
        $templateSize = $template.Length

        try {
            $templateContent = Get-Content $template.FullName -Raw -ErrorAction SilentlyContinue
            if ($templateContent) {
                if ($templateContent -match "(?i)EMA|ExponentialMovingAverage|Exponential") { $hasEMA = $true }
                if ($templateContent -match "(?i)\bRSI\b|RelativeStrengthIndex|Relative.?Strength") { $hasRSI = $true }
                if ($templateContent -match "(?i)MACD") { $hasMACD = $true }

                # Count EMA instances (we need at least 2: EMA(9) and EMA(21))
                $emaMatches = [regex]::Matches($templateContent, "(?i)EMA|ExponentialMovingAverage")
                $emaCount = $emaMatches.Count
            }
        } catch {
            Write-Host "WARNING: Could not read template file"
        }
    }

    # Also list all new templates (not in baseline)
    $newTemplates = @()
    Get-ChildItem $templateDir -ErrorAction SilentlyContinue | ForEach-Object {
        if ($baseline.existing_templates -notcontains $_.Name) {
            $newTemplates += $_.Name
        }
    }
}

# Check workspace modification
$workspaceModified = $false
if (Test-Path $wsDir) {
    $taskStart = Get-Content "$outputDir\task_start_timestamp.txt" -ErrorAction SilentlyContinue
    if ($taskStart) {
        $startEpoch = [int]$taskStart.Trim()
        Get-ChildItem $wsDir -Filter "*.xml" -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne "_Workspaces.xml"
        } | ForEach-Object {
            $fileEpoch = [int](Get-Date $_.LastWriteTime -UFormat %s)
            if ($fileEpoch -gt $startEpoch) {
                $workspaceModified = $true
            }
        }
    }
}

# Create result JSON
$result = @{
    template_found = $templateFound
    template_path = $templatePath
    template_size = $templateSize
    has_ema = $hasEMA
    has_rsi = $hasRSI
    has_macd = $hasMACD
    ema_count = $emaCount
    workspace_modified = $workspaceModified
    new_templates = $newTemplates
    export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "create_reusable_chart_template_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
