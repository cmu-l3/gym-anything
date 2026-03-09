# Setup script for work_item_triage_and_query task.
# Creates area paths, removes assignees from P1 bugs, sets wrong area path,
# then opens Edge to Work Items view.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_work_item_triage.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up work_item_triage_and_query task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Clean-DesktopForTask
    $baseUrl = Wait-AzureDevOpsReady -TimeoutSeconds 120
    Write-Host "Azure DevOps URL: $baseUrl"

    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # -----------------------------------------------------------------------
    # Step 1: Create area paths (Backend API and Uncategorized)
    # -----------------------------------------------------------------------
    Write-Host "Creating area paths..."
    $areaPaths = @("Backend API", "Uncategorized")
    foreach ($areaName in $areaPaths) {
        try {
            $areaBody = '{"name":"' + $areaName + '"}'
            Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/classificationnodes/areas?api-version=7.0" -Method "POST" -Body $areaBody | Out-Null
            Write-Host "  Created area: $areaName"
        } catch {
            Write-Host "  Area '$areaName' may already exist: $_"
        }
    }
    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # Step 2: Find all Priority 1 bugs via WIQL
    # -----------------------------------------------------------------------
    Write-Host "Querying Priority 1 bugs..."
    $bugWiql = '{"query": "SELECT [System.Id], [System.Title], [System.AssignedTo], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.WorkItemType] = ''Bug'' AND [Microsoft.VSTS.Common.Priority] = 1 ORDER BY [System.Id]"}'
    $bugResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $bugWiql
    $bugIds = @($bugResult.workItems | Select-Object -ExpandProperty id)

    Write-Host "Found $($bugIds.Count) Priority 1 bugs: $($bugIds -join ', ')"

    # -----------------------------------------------------------------------
    # Step 3: For each P1 bug:
    #   - Clear AssignedTo (unassign)
    #   - Set area path to TailwindTraders\Uncategorized
    #   - Clear tags
    # -----------------------------------------------------------------------
    $modifiedIds = @()
    foreach ($bugId in $bugIds) {
        try {
            $patchOps = @(
                @{ "op" = "add"; "path" = "/fields/System.AssignedTo"; "value" = "" },
                @{ "op" = "add"; "path" = "/fields/System.AreaPath"; "value" = "TailwindTraders\\Uncategorized" },
                @{ "op" = "add"; "path" = "/fields/System.Tags"; "value" = "" }
            )
            $patchBody = ConvertTo-Json -InputObject @($patchOps) -Depth 10

            Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($bugId)?api-version=7.0" -Method "PATCH" -Body $patchBody -ContentType "application/json-patch+json" | Out-Null
            $modifiedIds += $bugId
            Write-Host "  Bug #${bugId}: unassigned, moved to Uncategorized, tags cleared"
        } catch {
            Write-Host "  WARNING: Could not modify bug #$bugId : $_"
        }
    }

    # -----------------------------------------------------------------------
    # Step 4: Remove any existing "Critical Bug Backlog" shared queries
    # -----------------------------------------------------------------------
    Write-Host "Removing any existing 'Critical Bug Backlog' shared queries..."
    try {
        $sharedQueries = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries/Shared%20Queries?`$depth=2&api-version=7.0"
        if ($sharedQueries.children) {
            foreach ($child in $sharedQueries.children) {
                if ($child.name -match "Critical Bug Backlog") {
                    Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries/$($child.id)?api-version=7.0" -Method "DELETE" | Out-Null
                    Write-Host "  Removed query: $($child.name)"
                }
            }
        }
    } catch {
        Write-Host "  No shared queries to remove or error: $_"
    }

    # -----------------------------------------------------------------------
    # Step 5: Save baseline
    # -----------------------------------------------------------------------
    $baseline = @{
        p1_bug_ids = $bugIds
        p1_bug_count = $bugIds.Count
        initial_assignee = ""
        initial_area_path = "TailwindTraders\\Uncategorized"
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $baseline | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\task_results\work_item_triage_baseline.json" -Encoding UTF8 -Force
    Write-Host "Baseline saved."

    # -----------------------------------------------------------------------
    # Step 6: Open Edge to Work Items view
    # -----------------------------------------------------------------------
    $workItemsUrl = "$baseUrl/TailwindTraders/_workitems"
    Write-Host "Opening Work Items at: $workItemsUrl"
    Launch-EdgeInteractive -Url $workItemsUrl -WaitSeconds 12

    Write-Host "=== work_item_triage_and_query setup complete. $($bugIds.Count) P1 bugs unassigned and miscategorized. ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
