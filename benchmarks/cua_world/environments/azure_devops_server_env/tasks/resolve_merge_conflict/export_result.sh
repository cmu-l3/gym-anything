# Note: In the Azure DevOps Windows environment, this maps to export_result.ps1

<#
.SYNOPSIS
    Exports the result of the resolve_merge_conflict task.
    Checks Git history, file content, and PR status.
#>

$ErrorActionPreference = "Continue" # Don't crash on API errors, we need to report failure

# Load initial state
if (Test-Path "C:\Users\Docker\task_initial_state.json") {
    $InitialState = Get-Content "C:\Users\Docker\task_initial_state.json" | ConvertFrom-Json
    $PrId = $InitialState.pr_id
    $RepoId = $InitialState.repo_id
    $TaskStartTime = $InitialState.start_time
} else {
    Write-Host "Initial state not found!"
    $PrId = 1
    $RepoId = "" # Will fail later
    $TaskStartTime = 0
}

$BaseUrl = "http://localhost/DefaultCollection"
$ProjectName = "TailwindTraders"
$Password = "GymAnything123!"
$AuthHeader = @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Password"))}

$Result = @{
    task_start = $TaskStartTime
    task_end = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    pr_status = "unknown"
    pr_merge_status = "unknown"
    file_content_valid = $false
    conflict_markers_found = $false
    content_check = @{
        base_url_v2 = $false
        api_version_exists = $false
        retry_policy_exists = $false
    }
    commit_history_valid = $false
}

# ---------------------------------------------------------
# 1. Check PR Status
# ---------------------------------------------------------
try {
    $PrUri = "$BaseUrl/$ProjectName/_apis/git/repositories/$RepoId/pullrequests/$PrId`?api-version=6.0"
    $PrInfo = Invoke-RestMethod -Uri $PrUri -Headers $AuthHeader -Method Get
    $Result.pr_status = $PrInfo.status
    $Result.pr_merge_status = $PrInfo.mergeStatus
} catch {
    Write-Host "Failed to get PR info: $_"
}

# ---------------------------------------------------------
# 2. Get File Content (appsettings.json from master)
# ---------------------------------------------------------
try {
    # Get raw content of appsettings.json from master branch
    $FileUri = "$BaseUrl/$ProjectName/_apis/git/repositories/$RepoId/items?path=/appsettings.json&versionDescriptor.version=master&includeContent=true&api-version=6.0"
    $FileResponse = Invoke-RestMethod -Uri $FileUri -Headers $AuthHeader -Method Get
    $RawContent = $FileResponse.content

    # Check for conflict markers
    if ($RawContent -match "<<<<<<<" -or $RawContent -match "=======" -or $RawContent -match ">>>>>>>") {
        $Result.conflict_markers_found = $true
    }

    # Try parse JSON
    try {
        $JsonContent = $RawContent | ConvertFrom-Json
        $Result.file_content_valid = $true

        # Verify Content
        if ($JsonContent.ApiSettings.BaseUrl -eq "https://api.tailwindtraders.com/v2") {
            $Result.content_check.base_url_v2 = $true
        }
        if ($JsonContent.ApiSettings.ApiVersion -eq "2.0") {
            $Result.content_check.api_version_exists = $true
        }
        if ($JsonContent.RetryPolicy.MaxRetries -eq 3) {
            $Result.content_check.retry_policy_exists = $true
        }
    } catch {
        $Result.file_content_valid = $false
        Write-Host "JSON Parse Error: $_"
    }

    $Result.raw_content_preview = $RawContent.Substring(0, [Math]::Min($RawContent.Length, 500))

} catch {
    Write-Host "Failed to get file content: $_"
}

# ---------------------------------------------------------
# 3. Verify Commit History (Anti-Gaming)
# ---------------------------------------------------------
try {
    # Get commits on master
    $CommitsUri = "$BaseUrl/$ProjectName/_apis/git/repositories/$RepoId/commits?searchCriteria.itemVersion.version=master&top=1&api-version=6.0"
    $Commits = Invoke-RestMethod -Uri $CommitsUri -Headers $AuthHeader -Method Get
    
    if ($Commits.count -gt 0) {
        $LastCommit = $Commits.value[0]
        # ADO dates are ISO8601, parse to unix
        $CommitDate = [DateTimeOffset]::Parse($LastCommit.committer.date).ToUnixTimeSeconds()
        
        $Result.last_commit_timestamp = $CommitDate
        if ($CommitDate -gt $TaskStartTime) {
            $Result.commit_history_valid = $true
        }
    }
} catch {
    Write-Host "Failed to check history: $_"
}

# ---------------------------------------------------------
# 4. Save Result
# ---------------------------------------------------------
$ResultJson = $Result | ConvertTo-Json -Depth 5
$ResultJson | Out-File "C:\Users\Docker\task_result.json" -Encoding utf8

Write-Host "Result saved to C:\Users\Docker\task_result.json"