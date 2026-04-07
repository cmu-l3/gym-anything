# Note: This content corresponds to 'export_result.ps1' for the Windows environment.

# FILE: export_result.ps1
Write-Host "=== Exporting Augmented Sales Summary Result ==="

$docPath = "C:\Users\Docker\Documents"
$dvaPath = "$docPath\Augmented_Summary.dva"
$jsonPath = "C:\Temp\task_result.json"
$startTimePath = "C:\Temp\task_start_time.txt"
$extractPath = "C:\Temp\DVA_Extract"

# Initialize results
$result = @{
    output_exists = $false
    file_created_during_task = $false
    output_size_bytes = 0
    viz_bar_found = $false
    viz_narrative_found = $false
    columns_verified = $false
    timestamp = (Get-Date).ToString("o")
}

# Check file existence
if (Test-Path $dvaPath) {
    $result.output_exists = $true
    $fileInfo = Get-Item $dvaPath
    $result.output_size_bytes = $fileInfo.Length

    # Check timestamp
    if (Test-Path $startTimePath) {
        $startTime = [int64](Get-Content $startTimePath)
        $modTime = [int64](($fileInfo.LastWriteTime) - (Get-Date "1/1/1970")).TotalSeconds
        if ($modTime -gt $startTime) {
            $result.file_created_during_task = $true
        }
    } else {
        # Fallback if start time missing: assume true if file exists now (weak check)
        $result.file_created_during_task = $true 
    }

    # Inspect DVA content (DVA is a ZIP file)
    try {
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        Expand-Archive -Path $dvaPath -DestinationPath $extractPath -Force
        
        # Search relevant XML/JSON for visualization types
        # Keywords: 'nativeBar' (often used for bar charts), 'narrative' or 'nlg' for Language Narrative
        $contentFiles = Get-ChildItem -Path $extractPath -Recurse -Include *.xml,*.json,*.js
        
        foreach ($file in $contentFiles) {
            $text = Get-Content $file.FullName -Raw
            
            if ($text -match "nativeBar" -or $text -match "bar") {
                $result.viz_bar_found = $true
            }
            if ($text -match "narrative" -or $text -match "languageNarrative" -or $text -match "nlg") {
                $result.viz_narrative_found = $true
            }
            if ($text -match "Region" -and ($text -match "Sales" -or $text -match "Revenue")) {
                $result.columns_verified = $true
            }
        }
    } catch {
        Write-Host "Error inspecting DVA content: $_"
    }
}

# Convert to JSON and save
$json = $result | ConvertTo-Json
Set-Content -Path $jsonPath -Value $json
Write-Host "Result saved to $jsonPath"
Write-Host $json