# Note: In the Azure DevOps Windows environment, this maps to setup_task.ps1
# We provide the PowerShell content below, which the environment will execute.

<#
.SYNOPSIS
    Sets up the resolve_merge_conflict task.
    Creates a Git repo, commits conflicting changes, and opens a PR.
#>

$ErrorActionPreference = "Stop"

# Configuration
$BaseUrl = "http://localhost/DefaultCollection"
$ProjectName = "TailwindTraders"
$RepoName = "TailwindTraders-Api"
$Username = "Docker"
$Password = "GymAnything123!"
$Pat = "gn54v45q45q45q45q45q45q45q45q45q45q45q45q45q45q45q45" # Dummy, we use NTLM/Basic usually or just run as user

# Create temp workspace
$WorkDir = "C:\Users\Docker\AppData\Local\Temp\TaskSetup"
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
Set-Location $WorkDir

# Record start time
$StartTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$StartTime | Out-File "C:\Users\Docker\task_start_time.txt" -Encoding ascii

# ---------------------------------------------------------
# 1. Initialize Git Repo
# ---------------------------------------------------------
Write-Host "Initializing Git Repository..."
git init .
git config user.email "admin@tailwindtraders.com"
git config user.name "Tailwind Admin"

# Initial appsettings.json
$InitialJson = @{
    "ApiSettings" = @{
        "BaseUrl" = "https://api.tailwindtraders.com/v1"
        "Timeout" = 30
        "EnableLogging" = $true
    }
    "Database" = @{
        "ConnectionString" = "Server=sql01;Database=TailwindTraders;Trusted_Connection=true;"
        "MaxPoolSize" = 100
    }
    "Caching" = @{
        "Enabled" = $true
        "DefaultExpirationMinutes" = 15
    }
} | ConvertTo-Json -Depth 4

$InitialJson | Out-File "appsettings.json" -Encoding utf8
git add .
git commit -m "Initial configuration"

# ---------------------------------------------------------
# 2. Create 'main' state (The Update)
# ---------------------------------------------------------
# Create branch for update
git checkout -b feature/update-api-endpoint

$MainJson = @{
    "ApiSettings" = @{
        "BaseUrl" = "https://api.tailwindtraders.com/v2"
        "ApiVersion" = "2.0"
        "Timeout" = 30
        "EnableLogging" = $true
    }
    "Database" = @{
        "ConnectionString" = "Server=sql01;Database=TailwindTraders;Trusted_Connection=true;"
        "MaxPoolSize" = 100
    }
    "Caching" = @{
        "Enabled" = $true
        "DefaultExpirationMinutes" = 15
    }
} | ConvertTo-Json -Depth 4

$MainJson | Out-File "appsettings.json" -Encoding utf8
git commit -am "Update API to v2 and add versioning"

# Switch back to master/main and merge
git checkout master
git merge feature/update-api-endpoint
git branch -d feature/update-api-endpoint

# ---------------------------------------------------------
# 3. Create 'feature' state (The Conflict)
# ---------------------------------------------------------
# Go back to initial commit to branch off
$InitialCommit = git rev-list --max-parents=0 HEAD
git checkout -b feature/add-retry-config $InitialCommit

$FeatureJson = @{
    "ApiSettings" = @{
        "BaseUrl" = "https://api.tailwindtraders.com/v1/stable" # Conflict here
        "Timeout" = 30
        "EnableLogging" = $true
    }
    "RetryPolicy" = @{
        "MaxRetries" = 3
        "RetryDelayMs" = 1000
        "EnableCircuitBreaker" = $true
    }
    "Database" = @{
        "ConnectionString" = "Server=sql01;Database=TailwindTraders;Trusted_Connection=true;"
        "MaxPoolSize" = 100
    }
    "Caching" = @{
        "Enabled" = $true
        "DefaultExpirationMinutes" = 15
    }
} | ConvertTo-Json -Depth 4

$FeatureJson | Out-File "appsettings.json" -Encoding utf8
git commit -am "Add retry policy and stabilize endpoint"

# ---------------------------------------------------------
# 4. Push to Azure DevOps
# ---------------------------------------------------------
# We assume the project exists (created by env setup). We create the repo via API first if needed,
# or just push to a new repo URL.

# Setup auth header
$AuthHeader = @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Password"))}

# Create Repo via API
$RepoUrl = "$BaseUrl/$ProjectName/_apis/git/repositories?api-version=6.0"
$RepoBody = @{
    name = $RepoName
    project = @{ name = $ProjectName }
} | ConvertTo-Json

try {
    # Check if repo exists, delete if so to ensure clean state
    $Existing = Invoke-RestMethod -Uri "$RepoUrl" -Headers $AuthHeader -Method Get -ErrorAction SilentlyContinue
    $RepoId = $Existing.value | Where-Object { $_.name -eq $RepoName } | Select-Object -ExpandProperty id
    if ($RepoId) {
        Invoke-RestMethod -Uri "$BaseUrl/$ProjectName/_apis/git/repositories/$($RepoId)?api-version=6.0" -Headers $AuthHeader -Method Delete
    }
} catch {}

# Create new
$NewRepo = Invoke-RestMethod -Uri $RepoUrl -Headers $AuthHeader -Method Post -Body $RepoBody -ContentType "application/json"
$RemoteUrl = $NewRepo.remoteUrl -replace "http://", "http://$($Username):$($Password)@"

# Push
git remote add origin $RemoteUrl
git push -u origin master
git push -u origin feature/add-retry-config

# ---------------------------------------------------------
# 5. Create Pull Request
# ---------------------------------------------------------
$PrBody = @{
    sourceRefName = "refs/heads/feature/add-retry-config"
    targetRefName = "refs/heads/master"
    title = "Add retry and circuit breaker configuration"
    description = "Adds retry policy settings. Note: May conflict with recent API updates."
} | ConvertTo-Json

$PrUrl = "$BaseUrl/$ProjectName/_apis/git/repositories/$($NewRepo.id)/pullrequests?api-version=6.0"
$PrResponse = Invoke-RestMethod -Uri $PrUrl -Headers $AuthHeader -Method Post -Body $PrBody -ContentType "application/json"

# Save initial state info
@{
    pr_id = $PrResponse.pullRequestId
    repo_id = $NewRepo.id
    start_time = $StartTime
} | ConvertTo-Json | Out-File "C:\Users\Docker\task_initial_state.json" -Encoding ascii

# ---------------------------------------------------------
# 6. Launch Browser
# ---------------------------------------------------------
$PrWebUrl = "$BaseUrl/$ProjectName/_git/$RepoName/pullrequest/$($PrResponse.pullRequestId)"

# Start Edge
Start-Process "msedge" -ArgumentList $PrWebUrl,"--start-maximized"

# Wait for window
Start-Sleep -Seconds 5
$wshell = New-Object -ComObject wscript.shell
$wshell.AppActivate("Edge")
Start-Sleep -Seconds 1

Write-Host "=== Task setup complete ==="