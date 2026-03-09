# Note: This is PowerShell code for the Windows environment (export_result.ps1)

Write-Host "=== Exporting Results ==="

# 1. Paths
$dataDir = "C:\Users\Docker\Documents\TaskData"
$pbixPath = "$dataDir\IMDB_Analysis.pbix"
$csvPath = "$dataDir\genre_stats.csv"
$resultJson = "C:\tmp\task_result.json"
$tempExtractDir = "C:\tmp\pbix_extract"

# 2. Close Power BI to release file locks
Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# 3. Check Artifacts
$pbixExists = Test-Path $pbixPath
$csvExists = Test-Path $csvPath
$pbixSize = 0
if ($pbixExists) { $pbixSize = (Get-Item $pbixPath).Length }
$csvSize = 0
if ($csvExists) { $csvSize = (Get-Item $csvPath).Length }

# 4. Anti-gaming: Check timestamps
$startTime = 0
if (Test-Path "C:\tmp\task_start_time.txt") {
    $startTime = [int64](Get-Content "C:\tmp\task_start_time.txt")
}
$fileCreatedDuringTask = $false
if ($pbixExists) {
    $creationTime = [DateTimeOffset]::new((Get-Item $pbixPath).CreationTime).ToUnixTimeSeconds()
    $writeTime = [DateTimeOffset]::new((Get-Item $pbixPath).LastWriteTime).ToUnixTimeSeconds()
    if ($writeTime -gt $startTime) {
        $fileCreatedDuringTask = $true
    }
}

# 5. Inspect PBIX Internal Structure (Layout/Visuals)
$visualTypes = @()
if ($pbixExists) {
    # PBIX is a zip file. Extract Report/Layout
    if (Test-Path $tempExtractDir) { Remove-Item $tempExtractDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempExtractDir | Out-Null
    
    try {
        Expand-Archive -Path $pbixPath -DestinationPath $tempExtractDir -Force
        $layoutPath = "$tempExtractDir\Report\Layout"
        
        if (Test-Path $layoutPath) {
            # Layout is often UCS-2 LE BOM. Read cleanly.
            $layoutJson = Get-Content $layoutPath -Encoding Unicode -Raw | ConvertFrom-Json
            
            # Extract visual types from sections -> visualContainers -> config
            foreach ($section in $layoutJson.sections) {
                foreach ($vis in $section.visualContainers) {
                    try {
                        $config = $vis.config | ConvertFrom-Json
                        if ($config.singleVisual.visualType) {
                            $visualTypes += $config.singleVisual.visualType
                        }
                    } catch {}
                }
            }
        }
    } catch {
        Write-Warning "Could not extract or parse PBIX layout: $_"
    }
}

# 6. Generate JSON Result
$result = @{
    pbix_exists = $pbixExists
    pbix_size = $pbixSize
    csv_exists = $csvExists
    csv_size = $csvSize
    created_during_task = $fileCreatedDuringTask
    visual_types = $visualTypes
}

$result | ConvertTo-Json -Depth 10 | Set-Content $resultJson

Write-Host "Result exported to $resultJson"
Get-Content $resultJson