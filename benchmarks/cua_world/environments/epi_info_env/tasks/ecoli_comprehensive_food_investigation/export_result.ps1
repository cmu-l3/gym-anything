# Export: ecoli_comprehensive_food_investigation

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting ecoli_comprehensive_food_investigation Result ==="

$resultPath  = "C:\Users\Docker\ecoli_comprehensive_food_investigation_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_ecoli_comprehensive.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

function Get-FileResult {
    param([string]$FilePath, [bool]$ReadContent = $false, [int]$MaxLen = 2000)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $content = ""
        if ($ReadContent) {
            try {
                $raw = [System.IO.File]::ReadAllText($FilePath)
                $content = if ($raw.Length -gt $MaxLen) { $raw.Substring(0, $MaxLen) } else { $raw }
            } catch {}
        }
        return @{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)
            content    = $content
        }
    }
    return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false; content = "" }
}

$htmlPath = "C:\Users\Docker\ecoli_food_investigation.html"
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\ecoli_food_investigation.htm" }
$htmlResult = Get-FileResult $htmlPath -ReadContent $true -MaxLen 80000
$csvResult  = Get-FileResult "C:\Users\Docker\ecoli_risk_factors.csv" -ReadContent $true -MaxLen 5000

$htmlLower = $htmlResult.content.ToLower()

# Check for various food variables in the output
$foodVars = @("hamburger","hotdog","watermelon","lettuce","mustard","relish","ketchup","onion","peppers","corn","tomato","groundmeat")
$foodVarCount = 0
foreach ($v in $foodVars) {
    if ($htmlLower.Contains($v)) { $foodVarCount++ }
}

$hasFreqKw        = $htmlLower.Contains("frequency") -or $htmlLower.Contains("freq")
$hasTablesKw      = $htmlLower.Contains("odds ratio") -or $htmlLower.Contains("tables") -or $htmlLower.Contains("chi")
$hasLogisticKw    = $htmlLower.Contains("logistic") -or $htmlLower.Contains("regression")
$hasOrValues      = ($htmlLower -match "\d+\.\d+") -and ($htmlLower.Contains("odds") -or $htmlLower.Contains("ratio") -or $htmlLower.Contains("confidence"))
$hasEpiCurveKw    = $htmlLower.Contains("onset") -or $htmlLower.Contains("date") -or $htmlLower.Contains("epi curve")
$hasIlldum        = $htmlLower.Contains("illdum") -or $htmlLower.Contains("ill")
$multipleFoodTbls = $foodVarCount -ge 5

$result = [ordered]@{
    task        = "ecoli_comprehensive_food_investigation"
    task_start  = $taskStart
    html_output = @{
        exists           = $htmlResult.exists
        size_bytes       = $htmlResult.size_bytes
        mtime_unix       = $htmlResult.mtime_unix
        is_new           = $htmlResult.is_new
        has_freq_kw      = $hasFreqKw
        has_tables_kw    = $hasTablesKw
        has_logistic_kw  = $hasLogisticKw
        has_or_values    = $hasOrValues
        has_epi_curve_kw = $hasEpiCurveKw
        has_illdum       = $hasIlldum
        food_var_count   = $foodVarCount
        multiple_food_tables = $multipleFoodTbls
    }
    csv_output  = @{
        exists     = $csvResult.exists
        size_bytes = $csvResult.size_bytes
        mtime_unix = $csvResult.mtime_unix
        is_new     = $csvResult.is_new
    }
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "=== Export Complete ==="
