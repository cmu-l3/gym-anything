# Note: This is actually a PowerShell script saved with .ps1 extension in the environment
# The filename in the header will be export_result.ps1

<#
.SYNOPSIS
Export script for Query and Export Task
#>

Write-Host "=== Exporting Task Result ==="

$ResultFile = "C:\workspace\task_result.json"
$OutputPath = "C:\Users\Docker\Documents\chlorine_facilities.csv"
$StartTimeFile = "C:\workspace\task_start_time.txt"

# 1. Take Final Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Left, $Screen.Top, 0, 0, $Bitmap.Size)
$Bitmap.Save("C:\workspace\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
$Graphics.Dispose()
$Bitmap.Dispose()

# 2. Get Task Info
$TaskStart = 0
if (Test-Path $StartTimeFile) {
    $TaskStart = Get-Content $StartTimeFile
}
$TaskEnd = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds

# 3. Check Output File
$FileExists = $false
$FileCreatedDuringTask = $false
$Content = ""
$Size = 0

if (Test-Path $OutputPath) {
    $FileExists = $true
    $Item = Get-Item $OutputPath
    $Size = $Item.Length
    
    # Check timestamps (Windows file times need conversion to epoch for comparison)
    # CreationTime is local, convert to UTC epoch
    $CreationEpoch = [int64]($Item.CreationTimeUtc - (Get-Date "1/1/1970").ToUniversalTime()).TotalSeconds
    $LastWriteEpoch = [int64]($Item.LastWriteTimeUtc - (Get-Date "1/1/1970").ToUniversalTime()).TotalSeconds
    
    if ($LastWriteEpoch -gt $TaskStart) {
        $FileCreatedDuringTask = $true
    }
    
    # Read content (safely)
    try {
        $Content = Get-Content $OutputPath -Raw
    } catch {
        $Content = "ERROR_READING_FILE"
    }
}

# 4. Check App State
$AppRunning = $false
if (Get-Process "CAMEOfm" -ErrorAction SilentlyContinue) {
    $AppRunning = $true
}

# 5. Create JSON Result
# Escape content for JSON (basic escaping)
$EscapedContent = $Content -replace '\\', '\\\\' -replace '"', '\"' -replace "`r", '' -replace "`n", '\n'

$JsonContent = @"
{
    "task_start": $TaskStart,
    "task_end": $TaskEnd,
    "file_exists": $($FileExists.ToString().ToLower()),
    "file_created_during_task": $($FileCreatedDuringTask.ToString().ToLower()),
    "file_size": $Size,
    "file_content": "$EscapedContent",
    "app_running": $($AppRunning.ToString().ToLower())
}
"@

$JsonContent | Out-File -FilePath $ResultFile -Encoding ASCII

Write-Host "Result exported to $ResultFile"