# Export script for compute_incubation_period task
# Environment: Windows 11 (PowerShell)

Write-Host "=== Exporting Task Results ==="

# 1. Define Paths
$ResultsPath = "C:\Users\Docker\Documents\EpiInfoData\StigenOutbreak\incubation_results.txt"
$ExportJsonPath = "C:\Users\Docker\AppData\Local\Temp\task_result.json"
$TaskStartTimeFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# 2. Capture Final Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.X, $Screen.Y, 0, 0, $Screen.Size)
$Bitmap.Save("C:\Users\Docker\AppData\Local\Temp\task_final.png")

# 3. Check Result File
$OutputExists = $false
$FileCreatedDuringTask = $false
$OutputSize = 0
$Content = ""
$PathogenIdentified = ""

if (Test-Path $ResultsPath) {
    $OutputExists = $true
    $Item = Get-Item $ResultsPath
    $OutputSize = $Item.Length
    
    # Content Analysis
    $Content = Get-Content $ResultsPath -Raw
    
    # Simple check for pathogen names
    if ($Content -match "Norovirus") { $PathogenIdentified = "Norovirus" }
    elseif ($Content -match "Salmonella") { $PathogenIdentified = "Salmonella" }
    elseif ($Content -match "Staphylococcus") { $PathogenIdentified = "Staphylococcus" }
    
    # Check Timestamps
    if (Test-Path $TaskStartTimeFile) {
        $StartTimeStr = Get-Content $TaskStartTimeFile
        $StartTime = [DateTime]::ParseExact($StartTimeStr, "yyyy-MM-dd HH:mm:ss", $null)
        if ($Item.LastWriteTime -ge $StartTime) {
            $FileCreatedDuringTask = $true
        }
    } else {
        # Fallback if start time missing (assume true if file exists now)
        $FileCreatedDuringTask = $true
    }
}

# 4. Check App State
$AppRunning = $false
if (Get-Process "Analysis" -ErrorAction SilentlyContinue) {
    $AppRunning = $true
} elseif (Get-Process "EpiInfo" -ErrorAction SilentlyContinue) {
    $AppRunning = $true
}

# 5. Create JSON Result
$ResultObj = @{
    output_exists = $OutputExists
    file_created_during_task = $FileCreatedDuringTask
    output_size_bytes = $OutputSize
    app_was_running = $AppRunning
    pathogen_found = $PathogenIdentified
    content_preview = if ($Content.Length -gt 500) { $Content.Substring(0, 500) } else { $Content }
    screenshot_path = "C:\Users\Docker\AppData\Local\Temp\task_final.png"
}

$JsonContent = $ResultObj | ConvertTo-Json -Depth 2
Set-Content -Path $ExportJsonPath -Value $JsonContent

Write-Host "Result exported to $ExportJsonPath"
Write-Host $JsonContent
Write-Host "=== Export Complete ==="