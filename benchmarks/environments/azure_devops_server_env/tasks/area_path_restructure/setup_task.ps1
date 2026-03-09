# Note: This is actually a PowerShell script (setup_task.ps1) wrapped in bash logic 
# because the framework executes .sh hooks by default or expects the file extension in the command.
# In the task.json above, I specified "powershell ... setup_task.ps1".
# Below is the content for C:\workspace\tasks\area_path_restructure\setup_task.ps1

<#
.SYNOPSIS
    Sets up the initial state for the Area Path Restructure task.
    - Cleans existing work items
    - Resets Area Paths to default
    - Creates 8 specific work items at the root path
    - Launches Edge to the project backlog
#>

$ErrorActionPreference = "Stop"

# Configuration
$BaseUrl = "http://localhost/DefaultCollection"
$Project = "TailwindTraders"
$User = "Docker"
$Password = "GymAnything123!"
$Pair = "$($User):$($Password)"
$EncodedCreds = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Pair))
$Headers = @{ Authorization = "Basic $EncodedCreds" }

Write-Host "=== Setting up Area Path Restructure Task ==="

# 1. Record Start Time
$StartTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\task_results" | Out-Null
$StartTime | Out-File "C:\Users\Docker\task_results\task_start_time.txt" -Encoding ascii

# 2. Cleanup: Delete all existing work items to ensure clean state
try {
    $Wiql = @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '$Project'" }
    $Result = Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/wiql?api-version=6.0" -Method Post -Headers $Headers -Body ($Wiql | ConvertTo-Json) -ContentType "application/json"
    
    if ($Result.workItems.Count -gt 0) {
        Write-Host "Cleaning up $($Result.workItems.Count) existing work items..."
        foreach ($item in $Result.workItems) {
            Invoke-RestMethod -Uri "$BaseUrl/_apis/wit/workitems/$($item.id)?api-version=6.0" -Method Delete -Headers $Headers | Out-Null
        }
    }
} catch {
    Write-Warning "Cleanup failed or no items found: $_"
}

# 3. Cleanup: Remove Child Area Paths if they exist (Reset to root only)
try {
    $Areas = Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/classificationnodes/areas?$depth=1&api-version=6.0" -Method Get -Headers $Headers
    if ($Areas.children) {
        foreach ($child in $Areas.children) {
            Write-Host "Removing existing area: $($child.name)"
            # Note: Deleting classification nodes usually requires re-parenting items, but we deleted items first.
            try {
                Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/classificationnodes/areas/$($child.name)?api-version=6.0" -Method Delete -Headers $Headers | Out-Null
            } catch {
                Write-Warning "Could not delete area $($child.name). It might be in use."
            }
        }
    }
} catch {
    Write-Warning "Area cleanup failed: $_"
}

# 4. Create Initial Work Items at Root
$WorkItems = @(
    @{ Title = "Implement product search API endpoint"; Type = "User Story"; Priority = 1 },
    @{ Title = "Design REST API rate limiter middleware"; Type = "User Story"; Priority = 2 },
    @{ Title = "Fix product price rounding error"; Type = "Bug"; Priority = 1 },
    @{ Title = "Redesign shopping cart UI"; Type = "User Story"; Priority = 1 },
    @{ Title = "Fix CSS grid layout on product listing page"; Type = "Bug"; Priority = 2 },
    @{ Title = "Optimize dashboard lazy loading"; Type = "User Story"; Priority = 2 },
    @{ Title = "Configure CI/CD pipeline alerts"; Type = "User Story"; Priority = 3 },
    @{ Title = "Set up automated database backup schedule"; Type = "Task"; Priority = 2 }
)

Write-Host "Creating $($WorkItems.Count) initial work items..."

foreach ($item in $WorkItems) {
    $Body = @(
        @{ op = "add"; path = "/fields/System.Title"; value = $item.Title },
        @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority"; value = $item.Priority }
    ) | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/workitems/`$$($item.Type)?api-version=6.0" -Method Post -Headers $Headers -Body $Body -ContentType "application/json-patch+json" | Out-Null
        Write-Host "Created: $($item.Title)"
    } catch {
        Write-Error "Failed to create item '$($item.Title)': $_"
    }
}

# 5. Launch Edge to the Backlog
Write-Host "Launching Microsoft Edge..."
Stop-Process -Name "msedge" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process "msedge" -ArgumentList "$BaseUrl/$Project/_boards/board/t" -WindowStyle Maximized

# 6. Initial Screenshot
Start-Sleep -Seconds 5
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
$bitmap.Save("C:\Users\Docker\task_results\initial_state.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "=== Setup Complete ==="