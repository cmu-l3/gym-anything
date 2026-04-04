# Export script for sprint_health_audit task.
# Queries current state of Sprint 1 work items, team capacity, and work item comments.
# Writes result JSON for verifier.py.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_sprint_health_audit.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting sprint_health_audit result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    $baseUrl = Get-AzureDevOpsUrl
    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # -----------------------------------------------------------------------
    # Step 1: Load baseline
    # -----------------------------------------------------------------------
    $baselinePath = "C:\Users\Docker\task_results\sprint_health_audit_baseline.json"
    $baseline = @{ sprint1_item_ids = @(); total_story_points = 37; sprint1_item_count = 0 }
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
        } catch {
            Write-Host "WARNING: Could not parse baseline: $_"
        }
    }

    # -----------------------------------------------------------------------
    # Step 2: Query all project work items with iteration path and story points
    # -----------------------------------------------------------------------
    Write-Host "Querying all work items for story points and iteration paths..."
    $allWiqlBody = '{"query": "SELECT [System.Id], [System.Title], [System.WorkItemType], [System.IterationPath], [Microsoft.VSTS.Scheduling.StoryPoints], [Microsoft.VSTS.Common.Priority], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.WorkItemType] IN (''User Story'', ''Bug'') ORDER BY [System.Id]"}'

    $allResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $allWiqlBody
    $allIds = @($allResult.workItems | Select-Object -ExpandProperty id)

    $sprint1ItemsAfter = @()
    $movedItemIds = @()
    $sprint1PointsTotal = 0

    if ($allIds.Count -gt 0) {
        $idsChunk = ($allIds[0..[Math]::Min($allIds.Count - 1, 199)] -join ",")
        $fields = "System.Id,System.Title,System.IterationPath,Microsoft.VSTS.Scheduling.StoryPoints,Microsoft.VSTS.Common.Priority,System.WorkItemType"
        $itemsResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems?ids=$idsChunk&fields=$fields&api-version=7.0"

        foreach ($item in $itemsResult.value) {
            $iterPath = $item.fields."System.IterationPath"
            $pts = if ($item.fields.PSObject.Properties["Microsoft.VSTS.Scheduling.StoryPoints"] -and $item.fields."Microsoft.VSTS.Scheduling.StoryPoints") { [int]$item.fields."Microsoft.VSTS.Scheduling.StoryPoints" } else { 0 }
            $id = $item.id

            if ($iterPath -match "Sprint 1") {
                $sprint1ItemsAfter += $item
                $sprint1PointsTotal += $pts
            } elseif ($baseline.sprint1_item_ids -contains $id) {
                # Was in Sprint 1 before, now moved
                $movedItemIds += $id
            }
        }
    }

    Write-Host "Sprint 1 items after agent: $($sprint1ItemsAfter.Count)"
    Write-Host "Sprint 1 story points after agent: $sprint1PointsTotal"
    Write-Host "Items moved out of Sprint 1: $($movedItemIds.Count)"

    # -----------------------------------------------------------------------
    # Step 3: Check team capacity for Sprint 1
    # -----------------------------------------------------------------------
    Write-Host "Checking Sprint 1 team capacity..."
    $teamCapacitySet = $false
    $capacityDetails = @()

    try {
        # Get iterations
        $iterations = Invoke-AzDevOpsApi -Path "/TailwindTraders/TailwindTraders%20Team/_apis/work/teamsettings/iterations?api-version=7.0"
        $sprint1Iter = $iterations.value | Where-Object { $_.name -eq "Sprint 1" } | Select-Object -First 1

        if ($sprint1Iter) {
            $iterationId = $sprint1Iter.id
            $capacities = Invoke-AzDevOpsApi -Path "/TailwindTraders/TailwindTraders%20Team/_apis/work/teamsettings/iterations/$($iterationId)/capacities?api-version=7.0"

            foreach ($cap in $capacities.value) {
                $activity = $cap.activities | Where-Object { $_.capacityPerDay -gt 0 } | Select-Object -First 1
                if ($activity -and $activity.capacityPerDay -gt 0) {
                    $teamCapacitySet = $true
                }
                $capacityDetails += @{
                    member = $cap.teamMember.displayName
                    capacityPerDay = if ($activity) { $activity.capacityPerDay } else { 0 }
                }
            }
        }
    } catch {
        Write-Host "WARNING: Could not fetch team capacity: $_"
    }

    Write-Host "Team capacity set: $teamCapacitySet"

    # -----------------------------------------------------------------------
    # Step 4: Check for comments on moved work items
    # -----------------------------------------------------------------------
    $commentsFound = @()
    $allIdsToCheck = @($movedItemIds) + @($baseline.sprint1_item_ids | Where-Object { $sprint1ItemsAfter.id -notcontains $_ })

    foreach ($itemId in ($allIdsToCheck | Select-Object -Unique | Select-Object -First 10)) {
        try {
            $commentsResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workItems/$($itemId)/comments?api-version=7.0-preview.3"
            if ($commentsResult.count -gt 0) {
                $commentsFound += @{
                    item_id = $itemId
                    comment_count = $commentsResult.count
                    latest_comment = $commentsResult.comments[0].text
                }
            }
        } catch {
            # Comments API may not be available in all versions
            Write-Host "Could not fetch comments for item $itemId : $_"
        }
    }

    Write-Host "Items with comments (from moved set): $($commentsFound.Count)"

    # -----------------------------------------------------------------------
    # Step 5: Write result JSON
    # -----------------------------------------------------------------------
    $result = @{
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        baseline_sprint1_item_count = if ($baseline.sprint1_item_ids) { @($baseline.sprint1_item_ids).Count } else { 0 }
        baseline_story_points = $baseline.total_story_points
        sprint1_items_after_count = $sprint1ItemsAfter.Count
        sprint1_story_points_after = $sprint1PointsTotal
        items_moved_out_of_sprint1 = $movedItemIds.Count
        moved_item_ids = $movedItemIds
        team_capacity_set = $teamCapacitySet
        capacity_details = $capacityDetails
        items_with_comments = $commentsFound.Count
        comment_details = $commentsFound
    }

    $resultPath = "C:\Users\Docker\task_results\sprint_health_audit_result.json"
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
