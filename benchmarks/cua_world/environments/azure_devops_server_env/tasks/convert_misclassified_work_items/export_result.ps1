# Note: This is actually a PowerShell script (export_result.ps1) for the Windows environment.

<#
.SYNOPSIS
    Export script for convert_misclassified_work_items task
#>

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

$TaskResultsDir = "C:\Users\Docker\task_results"
$SetupDataFile = "$TaskResultsDir\setup_data.json"
$ResultFile = "$TaskResultsDir\task_result.json"
$ScreenshotPath = "$TaskResultsDir\final_screenshot.png"

# ADO Configuration
$CollectionUrl = "http://localhost/DefaultCollection"
$Project = "TailwindTraders"
$Username = "Docker"
$Password = "GymAnything123!"
$Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $Password)))
$Headers = @{Authorization=("Basic {0}" -f $Base64AuthInfo)}

# --- 1. Take Screenshot ---
Write-Host "Taking final screenshot..."
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen
$Bitmap = New-Object System.Drawing.Bitmap $Screen.Bounds.Width, $Screen.Bounds.Height
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Bounds.Location, [System.Drawing.Point]::Empty, $Screen.Bounds.Size)
$Bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$Graphics.Dispose()
$Bitmap.Dispose()
Write-Host "Screenshot saved to $ScreenshotPath"

# --- 2. Read Setup Data ---
if (Test-Path $SetupDataFile) {
    $SetupData = Get-Content $SetupDataFile | ConvertFrom-Json
    $BugId = $SetupData.bug_id
    $StoryId = $SetupData.story_id
} else {
    Write-Host "ERROR: Setup data not found!"
    # Fallback search if setup file missing
    $BugId = 0
    $StoryId = 0
}

# --- 3. Query Current State of Items ---
$Results = @{
    setup_found = $true
    item_101_id = $BugId
    item_101_type = "Unknown"
    item_101_desc = ""
    item_102_id = $StoryId
    item_102_type = "Unknown"
    screenshot_path = $ScreenshotPath
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

if ($BugId -gt 0) {
    try {
        $Uri = "$CollectionUrl/_apis/wit/workitems/$BugId`?api-version=6.0"
        $Item = Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers
        $Results.item_101_type = $Item.fields.'System.WorkItemType'
        $Results.item_101_desc = $Item.fields.'System.Description'
    } catch {
        Write-Host "Failed to query Item $BugId: $_"
    }
}

if ($StoryId -gt 0) {
    try {
        $Uri = "$CollectionUrl/_apis/wit/workitems/$StoryId`?api-version=6.0"
        $Item = Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers
        $Results.item_102_type = $Item.fields.'System.WorkItemType'
    } catch {
        Write-Host "Failed to query Item $StoryId: $_"
    }
}

# --- 4. Save Result ---
$Results | ConvertTo-Json | Out-File $ResultFile -Encoding utf8
Write-Host "Result saved to $ResultFile"
Get-Content $ResultFile
Write-Host "=== Export Complete ==="