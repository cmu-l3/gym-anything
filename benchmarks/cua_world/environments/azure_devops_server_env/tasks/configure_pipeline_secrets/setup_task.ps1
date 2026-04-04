# Note: This is a PowerShell script saved with .ps1 extension in the Windows environment
# The framework executes this via the command specified in hooks.pre_task

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Configure Pipeline Secrets Task ==="

# Define paths
$ProjectName = "TailwindTraders"
$CollectionUrl = "http://localhost/DefaultCollection"
$BaseUrl = "$CollectionUrl/$ProjectName/_apis"
$RepoUrl = "$BaseUrl/git/repositories/$ProjectName"

# timestamp
Get-Date -UFormat %s | Out-File -FilePath "C:\Users\Docker\task_start_time.txt" -Encoding ascii

# 1. Clean up: Delete Variable Group if it exists
try {
    $vgUrl = "$BaseUrl/distributedtask/variablegroups?groupName=PaymentService-Prod&api-version=6.0-preview.1"
    $vgs = Invoke-RestMethod -Uri $vgUrl -UseDefaultCredentials -Method Get
    
    if ($vgs.count -gt 0) {
        $vgId = $vgs.value[0].id
        Write-Host "Deleting existing Variable Group (ID: $vgId)..."
        $deleteUrl = "$BaseUrl/distributedtask/variablegroups/$vgId`?api-version=6.0-preview.1"
        Invoke-RestMethod -Uri $deleteUrl -UseDefaultCredentials -Method Delete
    }
} catch {
    Write-Warning "Failed to clean variable group: $_"
}

# 2. Reset azure-pipelines.yml to initial clean state
try {
    # Get Repo ID
    $repoResponse = Invoke-RestMethod -Uri "$RepoUrl" -UseDefaultCredentials
    $repoId = $repoResponse.id
    
    # Initial YAML content
    $initialYaml = @"
trigger:
- main

pool:
  name: Default

steps:
- script: echo "Building Payment Service..."
  displayName: 'Build'
"@

    # Push file via API
    $pushUrl = "$RepoUrl/pushes?api-version=6.0"
    
    # Get latest commit to base off
    $itemsUrl = "$RepoUrl/items?path=/&versionDescriptor.versionType=branch&versionDescriptor.version=main&api-version=6.0"
    $items = Invoke-RestMethod -Uri $itemsUrl -UseDefaultCredentials
    $oldObjectId = $items.value | Where-Object { $_.path -eq "/azure-pipelines.yml" } | Select-Object -ExpandProperty objectId -ErrorAction SilentlyContinue
    
    if (-not $oldObjectId) {
        $changeType = "add"
    } else {
        $changeType = "edit"
    }
    
    $oldCommit = Invoke-RestMethod -Uri "$RepoUrl/commits?top=1&api-version=6.0" -UseDefaultCredentials
    $oldCommitId = $oldCommit.value[0].commitId

    $body = @{
        refUpdates = @(
            @{
                name = "refs/heads/main"
                oldObjectId = $oldCommitId
            }
        )
        commits = @(
            @{
                comment = "Reset pipeline for task"
                changes = @(
                    @{
                        changeType = $changeType
                        item = @{
                            path = "/azure-pipelines.yml"
                        }
                        newContent = @{
                            content = $initialYaml
                            contentType = "rawtext"
                        }
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $pushUrl -Method Post -Body $body -ContentType "application/json" -UseDefaultCredentials
    Write-Host "Reset azure-pipelines.yml"
} catch {
    Write-Warning "Failed to reset pipeline file: $_"
    # Fallback: Assume it's okay or agent will fix
}

# 3. Open Browser to Library
Stop-Process -Name msedge -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process "msedge" "$CollectionUrl/$ProjectName/_build?_a=library"

# 4. Wait for window and Maximize (using simple powershell method)
Start-Sleep -Seconds 5
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
# Simple maximize via shell object if possible, or just trust the user interacts
$shell = New-Object -ComObject WScript.Shell
if ($shell.AppActivate("Edge")) {
    Start-Sleep -Milliseconds 500
    $shell.SendKeys("% x") # Alt+Space, x to maximize
}

# 5. Capture Initial Screenshot
# Using a PowerShell script to capture screen
$scriptBlock = {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save("C:\Users\Docker\task_initial.png")
    $graphics.Dispose()
    $bitmap.Dispose()
}
Invoke-Command -ScriptBlock $scriptBlock

Write-Host "=== Setup Complete ==="