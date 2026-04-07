# Note: This is actually a PowerShell script (setup_task.ps1) for the Windows environment
# but the file extension in the prompt request asked for .sh or appropriate format.
# Since the environment is Windows, the file MUST be .ps1 for the hooks to work.

<#
.SYNOPSIS
    Setup script for convert_misclassified_work_items task
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Convert Misclassified Work Items Task ==="

# Define paths
$TaskResultsDir = "C:\Users\Docker\task_results"
if (-not (Test-Path $TaskResultsDir)) {
    New-Item -ItemType Directory -Path $TaskResultsDir -Force | Out-Null
}
$SetupDataFile = "$TaskResultsDir\setup_data.json"
$StartTimeFile = "$TaskResultsDir\task_start_time.txt"

# Record start time
[int][double]::Parse((Get-Date -UFormat %s)) | Out-File $StartTimeFile -Encoding ascii

# ADO Configuration
$CollectionUrl = "http://localhost/DefaultCollection"
$Project = "TailwindTraders"
$BaseUrl = "$CollectionUrl/$Project/_apis/wit/workitems"
# Use basic auth with the default credentials provided in env
$Username = "Docker"
$Password = "GymAnything123!"
$Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $Password)))
$Headers = @{Authorization=("Basic {0}" -f $Base64AuthInfo)}

# --- 1. Clean up existing items with conflicting titles ---
Write-Host "Cleaning up old items..."
$Wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND ([System.Title] = 'Shopping Cart Redesign' OR [System.Title] = 'Update API Schema')"
$QueryUrl = "$CollectionUrl/$Project/_apis/wit/wiql?api-version=6.0"
try {
    $Response = Invoke-RestMethod -Uri $QueryUrl -Method Post -Body (@{query=$Wiql} | ConvertTo-Json) -ContentType "application/json" -Headers $Headers
    foreach ($Item in $Response.workItems) {
        $DeleteUrl = "$BaseUrl/$($Item.id)?api-version=6.0"
        Invoke-RestMethod -Uri $DeleteUrl -Method Delete -Headers $Headers | Out-Null
        Write-Host "Deleted old item ID $($Item.id)"
    }
} catch {
    Write-Host "Warning during cleanup: $_"
}

# --- 2. Create 'Shopping Cart Redesign' (Bug) ---
Write-Host "Creating 'Shopping Cart Redesign' Bug..."
$BugBody = @(
    @{ op="add"; path="/fields/System.Title"; value="Shopping Cart Redesign" },
    @{ op="add"; path="/fields/Microsoft.VSTS.TCM.ReproSteps"; value="Requirement: Add wish list button to the main cart dropdown. <br><div>This feature was requested by marketing.</div>" },
    @{ op="add"; path="/fields/System.Priority"; value=2 }
) | ConvertTo-Json

$BugUrl = "$BaseUrl/`$Bug?api-version=6.0"
$BugItem = Invoke-RestMethod -Uri $BugUrl -Method Post -Body $BugBody -ContentType "application/json-patch+json" -Headers $Headers
$BugId = $BugItem.id
Write-Host "Created Bug ID: $BugId"

# --- 3. Create 'Update API Schema' (User Story) ---
Write-Host "Creating 'Update API Schema' User Story..."
$StoryBody = @(
    @{ op="add"; path="/fields/System.Title"; value="Update API Schema" },
    @{ op="add"; path="/fields/System.Description"; value="Update the Swagger definition to match v2 specs." }
) | ConvertTo-Json

$StoryUrl = "$BaseUrl/`$User Story?api-version=6.0"
$StoryItem = Invoke-RestMethod -Uri $StoryUrl -Method Post -Body $StoryBody -ContentType "application/json-patch+json" -Headers $Headers
$StoryId = $StoryItem.id
Write-Host "Created User Story ID: $StoryId"

# --- 4. Save IDs for verification ---
$SetupData = @{
    bug_id = $BugId
    story_id = $StoryId
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$SetupData | ConvertTo-Json | Out-File $SetupDataFile -Encoding utf8

# --- 5. Launch Browser ---
Write-Host "Launching Microsoft Edge..."
$WorkItemsUrl = "$CollectionUrl/$Project/_workitems/recentlyupdated"

# Stop existing Edge instances
Stop-Process -Name "msedge" -ErrorAction SilentlyContinue

# Start Edge maximized
Start-Process "msedge" -ArgumentList "$WorkItemsUrl --start-maximized --new-window"

# Wait for window
Start-Sleep -Seconds 5
$wshell = New-Object -ComObject wscript.shell
if ($wshell.AppActivate("TailwindTraders")) {
    Write-Host "Browser focused."
}

Write-Host "=== Setup Complete ==="