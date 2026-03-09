# Setup script for sprint_health_audit task.
# Assigns story points to Sprint 1 work items (overloading it) so the agent
# must triage the sprint. Opens Edge to the Sprint 1 board view.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_sprint_health_audit.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up sprint_health_audit task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Clean desktop
    Clean-DesktopForTask

    # Ensure Azure DevOps is ready
    $baseUrl = Wait-AzureDevOpsReady -TimeoutSeconds 120
    Write-Host "Azure DevOps URL: $baseUrl"

    # Ensure output directory exists
    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # -----------------------------------------------------------------------
    # Step 1: Find Sprint 1 work items via WIQL
    # -----------------------------------------------------------------------
    Write-Host "Querying Sprint 1 work items..."
    $wiqlBody = '{"query": "SELECT [System.Id], [System.Title], [System.WorkItemType], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.IterationPath] UNDER ''TailwindTraders\\Sprint 1'' ORDER BY [System.Id]"}'

    $wiqlResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $wiqlBody
    $sprint1Ids = @($wiqlResult.workItems | Select-Object -ExpandProperty id)

    if ($sprint1Ids.Count -eq 0) {
        Write-Host "WARNING: No Sprint 1 work items found. Trying alternative iteration path..."
        $wiqlBody2 = '{"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.IterationPath] UNDER ''TailwindTraders\\Sprint 1'' ORDER BY [System.Id]"}'
        $wiqlResult2 = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $wiqlBody2
        $sprint1Ids = @($wiqlResult2.workItems | Select-Object -ExpandProperty id)
    }

    Write-Host "Found $($sprint1Ids.Count) Sprint 1 work items: $($sprint1Ids -join ', ')"

    # -----------------------------------------------------------------------
    # Step 2: Assign story points to Sprint 1 items
    # Story points map by work item type:
    #   User Stories -> StoryPoints field
    #   Bugs -> StoryPoints field (Agile template)
    # -----------------------------------------------------------------------
    # Points to assign per item index (capped at 5 items for safety)
    $pointsMap = @{
        0 = 13   # Largest user story
        1 = 8    # Second user story
        2 = 5    # Critical bug
        3 = 3    # Medium bug
        4 = 8    # Concurrency bug
    }

    $totalPointsAssigned = 0
    for ($i = 0; $i -lt [Math]::Min($sprint1Ids.Count, 5); $i++) {
        $itemId = $sprint1Ids[$i]
        $pts = $pointsMap[$i]

        # Get work item to check type
        $item = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($itemId)?fields=System.WorkItemType,System.Title&api-version=7.0"
        $workItemType = $item.fields."System.WorkItemType"
        Write-Host "  Setting $pts points on #$itemId ($workItemType): $($item.fields.'System.Title')"

        $patchBody = '[{"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.StoryPoints","value":' + $pts + '}]'
        try {
            Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($itemId)?api-version=7.0" -Method "PATCH" -Body $patchBody -ContentType "application/json-patch+json" | Out-Null
            $totalPointsAssigned += $pts
            Write-Host "    -> Story points set to $pts"
        } catch {
            Write-Host "    -> WARNING: Could not set story points on #$itemId : $_"
        }
    }

    Write-Host "Total story points assigned to Sprint 1: $totalPointsAssigned"

    # -----------------------------------------------------------------------
    # Step 3: Save baseline state
    # -----------------------------------------------------------------------
    $baseline = @{
        sprint1_item_ids = $sprint1Ids
        sprint1_item_count = $sprint1Ids.Count
        total_story_points = $totalPointsAssigned
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $baseline | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\task_results\sprint_health_audit_baseline.json" -Encoding UTF8 -Force
    Write-Host "Baseline saved."

    # -----------------------------------------------------------------------
    # Step 4: Open Edge to Sprint 1 view
    # -----------------------------------------------------------------------
    $sprintUrl = "$baseUrl/TailwindTraders/_sprints/taskboard/TailwindTraders%20Team/TailwindTraders/Sprint%201"
    Write-Host "Opening Sprint 1 view: $sprintUrl"
    Launch-EdgeInteractive -Url $sprintUrl -WaitSeconds 12

    $edgeProc = Get-Process msedge -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($edgeProc) {
        Write-Host "Edge running (PID: $($edgeProc.Id))"
    } else {
        Write-Host "WARNING: Edge not found after launch."
    }

    Write-Host "=== sprint_health_audit setup complete. Sprint 1 has $totalPointsAssigned story points. ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
