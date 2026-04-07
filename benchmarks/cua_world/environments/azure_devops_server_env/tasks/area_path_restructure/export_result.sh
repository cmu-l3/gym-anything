# Note: This is the content for C:\workspace\tasks\area_path_restructure\export_result.ps1
# The task.json hooks call this PowerShell script.

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

# Configuration
$BaseUrl = "http://localhost/DefaultCollection"
$Project = "TailwindTraders"
$User = "Docker"
$Password = "GymAnything123!"
$Pair = "$($User):$($Password)"
$EncodedCreds = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Pair))
$Headers = @{ Authorization = "Basic $EncodedCreds" }
$ResultPath = "C:\Users\Docker\task_results\area_path_restructure_result.json"
$StartTimePath = "C:\Users\Docker\task_results\task_start_time.txt"

# Get Start Time
$TaskStartTime = if (Test-Path $StartTimePath) { Get-Content $StartTimePath } else { (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ") }

# Data Collection Object
$ResultData = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    areas = @()
    work_items = @()
    task_start_time = $TaskStartTime
}

# 1. Fetch Area Paths
try {
    Write-Host "Fetching Area Paths..."
    $AreaResponse = Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/classificationnodes/areas?$depth=2&api-version=6.0" -Method Get -Headers $Headers
    
    if ($AreaResponse.children) {
        foreach ($child in $AreaResponse.children) {
            $ResultData.areas += $child.name
        }
    }
} catch {
    Write-Error "Failed to fetch areas: $_"
}

# 2. Fetch Work Items
try {
    Write-Host "Fetching Work Items..."
    $Wiql = @{ 
        query = "SELECT [System.Id], [System.Title], [System.AreaPath], [System.ChangedDate] FROM WorkItems WHERE [System.TeamProject] = '$Project'" 
    }
    $QueryResponse = Invoke-RestMethod -Uri "$BaseUrl/$Project/_apis/wit/wiql?api-version=6.0" -Method Post -Headers $Headers -Body ($Wiql | ConvertTo-Json) -ContentType "application/json"
    
    if ($QueryResponse.workItems) {
        $Ids = $QueryResponse.workItems | Select-Object -ExpandProperty id
        # Fetch details in chunks or loop (loop is safer for small N=8)
        foreach ($id in $Ids) {
            $Item = Invoke-RestMethod -Uri "$BaseUrl/_apis/wit/workitems/$id?api-version=6.0" -Method Get -Headers $Headers
            
            $ResultData.work_items += @{
                id = $Item.id
                title = $Item.fields.'System.Title'
                area_path = $Item.fields.'System.AreaPath'
                changed_date = $Item.fields.'System.ChangedDate'
            }
        }
    }
} catch {
    Write-Error "Failed to fetch work items: $_"
}

# 3. Take Final Screenshot
try {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    $bitmap.Save("C:\Users\Docker\task_results\final_state.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    $ResultData["screenshot_saved"] = $true
} catch {
    $ResultData["screenshot_saved"] = $false
    Write-Warning "Screenshot capture failed"
}

# 4. Save JSON Result
$ResultData | ConvertTo-Json -Depth 5 | Out-File $ResultPath -Encoding ascii

Write-Host "Result exported to $ResultPath"
Get-Content $ResultPath