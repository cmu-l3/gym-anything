# Setup script for release_notes_preparation task.
# Sets Sprint 1 work items to realistic end-of-sprint states:
#   - 5 items Resolved/Closed (completed work)
#   - 2 P1 bugs left Active (release blockers the agent must find)
#   - 1 P2 task left Active (not a blocker)
# Cleans up any prior release artifacts (branch, wiki page, tags).
# Opens Edge to the TailwindTraders project home.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_release_notes_preparation.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up release_notes_preparation task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Clean desktop
    Clean-DesktopForTask

    # Ensure Azure DevOps is ready
    $baseUrl = Wait-AzureDevOpsReady -TimeoutSeconds 120
    Write-Host "Azure DevOps URL: $baseUrl"

    # Ensure output directory exists and delete stale result files
    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null
    Remove-Item -Path "C:\Users\Docker\task_results\release_notes_preparation_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Users\Docker\task_results\release_notes_preparation_baseline.json" -Force -ErrorAction SilentlyContinue
    Write-Host "Stale result files cleaned."

    $repoApi = "/TailwindTraders/_apis/git/repositories/TailwindTraders"

    # -----------------------------------------------------------------------
    # Step 1: Delete release/v1.5.0 branch if it exists
    # -----------------------------------------------------------------------
    Write-Host "Cleaning up existing release branch..."
    try {
        $releaseRefs = Invoke-AzDevOpsApi -Path "$repoApi/refs?filter=heads/release/v1.5.0&api-version=7.0"
        if ($releaseRefs.value.Count -gt 0) {
            $oldSha = $releaseRefs.value[0].objectId
            $delBody = '[{"name":"refs/heads/release/v1.5.0","oldObjectId":"' + $oldSha + '","newObjectId":"0000000000000000000000000000000000000000"}]'
            Invoke-AzDevOpsApi -Path "$repoApi/refs?api-version=7.0" -Method "POST" -Body $delBody | Out-Null
            Write-Host "  Deleted existing release/v1.5.0 branch."
        } else {
            Write-Host "  No existing release/v1.5.0 branch."
        }
    } catch {
        Write-Host "  Could not check/delete release branch: $_"
    }

    # -----------------------------------------------------------------------
    # Step 2: Query all Sprint 1 work items
    # -----------------------------------------------------------------------
    Write-Host "Querying Sprint 1 work items..."
    $wiqlBody = '{"query": "SELECT [System.Id], [System.Title], [System.WorkItemType], [Microsoft.VSTS.Common.Priority], [System.State], [System.Tags] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.IterationPath] UNDER ''TailwindTraders\\Sprint 1'' ORDER BY [System.Id]"}'
    $wiqlResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $wiqlBody
    $sprint1Ids = @($wiqlResult.workItems | Select-Object -ExpandProperty id)
    Write-Host "Found $($sprint1Ids.Count) Sprint 1 work items: $($sprint1Ids -join ', ')"

    # Fetch full details of all Sprint 1 items
    $sprint1Items = @()
    if ($sprint1Ids.Count -gt 0) {
        $idsStr = ($sprint1Ids -join ",")
        $fields = "System.Id,System.Title,System.WorkItemType,Microsoft.VSTS.Common.Priority,System.State,System.Tags"
        $itemsResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems?ids=$idsStr&fields=$fields&api-version=7.0"
        $sprint1Items = $itemsResult.value
    }

    # -----------------------------------------------------------------------
    # Step 3: Set work item states for realistic end-of-sprint scenario
    # -----------------------------------------------------------------------
    Write-Host "Setting work item states..."

    # Define which items should be completed vs still active
    $completedTitles = @(
        "Implement product inventory search with full-text filtering",
        "Design REST API rate limiting and authentication middleware",
        "API returns 500 error when filtering products with special characters in category name",
        "Set up PostgreSQL database migration scripts for v2.0 schema changes",
        "Configure CI/CD pipeline for automated testing and staging deployment"
    )

    # These P1 bugs should remain Active (release blockers for agent to find)
    $blockerTitles = @(
        "Product price calculation returns incorrect values for bulk discount tiers",
        "Inventory count becomes negative after concurrent stock deduction requests"
    )

    $baselineItems = @()

    foreach ($item in $sprint1Items) {
        $id = $item.id
        $title = $item.fields."System.Title"
        $wiType = $item.fields."System.WorkItemType"
        $priority = $item.fields."Microsoft.VSTS.Common.Priority"
        $currentState = $item.fields."System.State"
        $currentTags = if ($item.fields."System.Tags") { $item.fields."System.Tags" } else { "" }

        $patchOps = @()

        # Remove any existing release-blocker tag from all items
        if ($currentTags -match "release-blocker") {
            $newTags = ($currentTags -split ";\s*" | Where-Object { $_ -ne "release-blocker" }) -join "; "
            $patchOps += '{"op":"replace","path":"/fields/System.Tags","value":"' + $newTags + '"}'
        }

        # Determine target state
        $targetState = $null
        $isCompleted = $false
        $isBlocker = $false

        foreach ($ct in $completedTitles) {
            if ($title -eq $ct) {
                $isCompleted = $true
                break
            }
        }
        foreach ($bt in $blockerTitles) {
            if ($title -eq $bt) {
                $isBlocker = $true
                break
            }
        }

        if ($isCompleted) {
            # Set to Resolved or Closed based on type
            if ($wiType -eq "Task") {
                $targetState = "Closed"
            } else {
                $targetState = "Resolved"
            }
        } elseif ($isBlocker) {
            $targetState = "Active"
        } else {
            # P2 active task or other items - set to Active
            $targetState = "Active"
        }

        if ($targetState -and $currentState -ne $targetState) {
            $patchOps += '{"op":"replace","path":"/fields/System.State","value":"' + $targetState + '"}'
        }

        # Apply patches if any
        if ($patchOps.Count -gt 0) {
            $patchBody = "[" + ($patchOps -join ",") + "]"
            try {
                Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($id)?api-version=7.0" -Method "PATCH" -Body $patchBody -ContentType "application/json-patch+json" | Out-Null
                Write-Host "  #$id '$title' ($wiType, P$priority) -> $targetState"
            } catch {
                Write-Host "  WARNING: Could not update #$id : $_"
            }
        } else {
            Write-Host "  #$id '$title' already in correct state ($currentState)"
        }

        $baselineItems += @{
            id = $id
            title = $title
            type = $wiType
            priority = $priority
            state = $targetState
            is_completed = $isCompleted
            is_blocker = $isBlocker
        }
    }

    # -----------------------------------------------------------------------
    # Step 4: Clean up existing wiki page if present
    # -----------------------------------------------------------------------
    Write-Host "Cleaning up existing wiki page..."
    try {
        $wikis = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis?api-version=7.0"
        foreach ($wiki in $wikis.value) {
            try {
                # Try to delete the specific page
                Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis/$($wiki.id)/pages?path=/Release%20v1.5.0&api-version=7.0" -Method "DELETE" | Out-Null
                Write-Host "  Deleted existing 'Release v1.5.0' wiki page from wiki '$($wiki.name)'"
            } catch {
                Write-Host "  No existing 'Release v1.5.0' page in wiki '$($wiki.name)' (OK)"
            }
        }
    } catch {
        Write-Host "  No wikis found or error: $_"
    }

    # Ensure a project wiki exists (create if needed so the agent only needs to add a page)
    try {
        $wikis = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis?api-version=7.0"
        $projectWiki = $wikis.value | Where-Object { $_.type -eq "projectWiki" } | Select-Object -First 1
        if (-not $projectWiki) {
            Write-Host "  No project wiki found. Creating one..."
            $repoInfo = Invoke-AzDevOpsApi -Path "$repoApi`?api-version=7.0"
            $projectInfo = Invoke-AzDevOpsApi -Path "/_apis/projects/TailwindTraders?api-version=7.0"
            $wikiBody = @{
                name = "TailwindTraders.wiki"
                type = "projectWiki"
                projectId = $projectInfo.id
            } | ConvertTo-Json -Depth 5
            try {
                Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis?api-version=7.0" -Method "POST" -Body $wikiBody | Out-Null
                Write-Host "  Project wiki created."
            } catch {
                Write-Host "  Could not create project wiki: $_ (agent may need to create it)"
            }
        } else {
            Write-Host "  Project wiki already exists: $($projectWiki.name)"
        }
    } catch {
        Write-Host "  Wiki check failed: $_"
    }

    # -----------------------------------------------------------------------
    # Step 5: Save baseline state
    # -----------------------------------------------------------------------
    $baseline = @{
        sprint1_items = $baselineItems
        sprint1_item_count = $baselineItems.Count
        completed_count = ($baselineItems | Where-Object { $_.is_completed }).Count
        blocker_count = ($baselineItems | Where-Object { $_.is_blocker }).Count
        release_branch_existed = $false
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $baseline | ConvertTo-Json -Depth 10 | Out-File -FilePath "C:\Users\Docker\task_results\release_notes_preparation_baseline.json" -Encoding UTF8 -Force
    Write-Host "Baseline saved."

    # -----------------------------------------------------------------------
    # Step 6: Open Edge to project home
    # -----------------------------------------------------------------------
    $projectUrl = "$baseUrl/TailwindTraders"
    Write-Host "Opening project home: $projectUrl"
    Launch-EdgeInteractive -Url $projectUrl -WaitSeconds 12

    $edgeProc = Get-Process msedge -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($edgeProc) {
        Write-Host "Edge running (PID: $($edgeProc.Id))"
    } else {
        Write-Host "WARNING: Edge not found after launch."
    }

    Write-Host "=== release_notes_preparation setup complete. ==="
    Write-Host "  Sprint 1 items: $($baselineItems.Count)"
    Write-Host "  Completed: $(($baselineItems | Where-Object { $_.is_completed }).Count)"
    Write-Host "  Blockers (Active P1 bugs): $(($baselineItems | Where-Object { $_.is_blocker }).Count)"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
