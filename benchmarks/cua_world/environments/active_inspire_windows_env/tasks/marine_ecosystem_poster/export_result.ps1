# Export result script for Create Marine Ecosystem Poster task

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Create Marine Ecosystem Poster task result ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Get task start time
$taskStart = 0
$taskStartFile = "C:\Windows\Temp\task_start_time"
if (Test-Path $taskStartFile) {
    $taskStart = [int](Get-Content $taskStartFile -Raw).Trim()
}

# Check for expected file
$expectedFile = "C:\Users\Docker\Documents\Flipcharts\marine_ecosystem.flipchart"
$expectedFileAlt = "C:\Users\Docker\Documents\Flipcharts\marine_ecosystem.flp"

$fileFound = $false
$filePath = ""
$fileSize = 0
$fileMtime = 0
$fileValid = $false
$createdDuringTask = $false
$pageCount = 0

# Check primary expected path
if (Test-Path $expectedFile) {
    $fileFound = $true
    $filePath = $expectedFile
} elseif (Test-Path $expectedFileAlt) {
    $fileFound = $true
    $filePath = $expectedFileAlt
}

if ($fileFound) {
    $fileInfo = Get-Item $filePath
    $fileSize = $fileInfo.Length
    $fileMtime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))
    $fileValid = ($fileSize -gt 0)

    if ($fileMtime -ge $taskStart) {
        $createdDuringTask = $true
    }

    # Try to extract and analyze flipchart content
    $tempDir = Join-Path $env:TEMP "flipchart_export_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        Expand-Archive -Path $filePath -DestinationPath $tempDir -Force -ErrorAction SilentlyContinue

        # Collect text from all XML files
        $allText = ""
        Get-ChildItem $tempDir -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $allText += (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue)
        }

        # Count pages
        $pageCount = (Get-ChildItem $tempDir -Filter "page*.xml" -ErrorAction SilentlyContinue).Count
        if ($pageCount -eq 0 -and $allText) {
            $pageCount = ([regex]::Matches($allText, "<[Pp]age")).Count
            if ($pageCount -eq 0) { $pageCount = 1 }
        }
    } catch {
        Write-Host "Could not extract flipchart: $_"
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# List all flipchart files
$allFlipcharts = ""
if (Test-Path "C:\Users\Docker\Documents\Flipcharts") {
    $files = Get-ChildItem "C:\Users\Docker\Documents\Flipcharts" -Include "*.flipchart","*.flp" -ErrorAction SilentlyContinue
    $allFlipcharts = ($files | ForEach-Object { $_.FullName }) -join ","
}

# Create JSON result
$result = @{
    file_found = $fileFound
    file_path = $filePath
    file_size = $fileSize
    file_mtime = $fileMtime
    file_valid = $fileValid
    page_count = $pageCount
    created_during_task = $createdDuringTask
    all_flipcharts = $allFlipcharts
    expected_path = $expectedFile
    timestamp = (Get-Date -Format "o")
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Windows\Temp\task_result.json"
[System.IO.File]::WriteAllText($resultPath, $resultJson)

Write-Host "Result saved to $resultPath"
Write-Host $resultJson
Write-Host "=== Export complete ==="
