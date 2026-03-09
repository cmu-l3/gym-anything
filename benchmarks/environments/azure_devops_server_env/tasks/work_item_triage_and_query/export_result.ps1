# Export script for work_item_triage_and_query task.
# Checks P1 bug assignees, area paths, tags, and shared queries.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_work_item_triage.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting work_item_triage_and_query result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # Load baseline
    $baselinePath = "C:\Users\Docker\task_results\work_item_triage_baseline.json"
    $p1BugIds = @()
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
            $p1BugIds = @($baseline.p1_bug_ids)
        } catch { }
    }

    # -----------------------------------------------------------------------
    # Step 1: Query P1 bugs with assignee, area path, tags
    # -----------------------------------------------------------------------
    Write-Host "Querying current P1 bug state..."
    $bugDetails = @()
    $assignedCount = 0
    $correctAreaCount = 0
    $taggedCount = 0

    if ($p1BugIds.Count -gt 0) {
        $idsStr = $p1BugIds -join ","
        $fields = "System.Id,System.Title,System.AssignedTo,System.AreaPath,System.Tags,Microsoft.VSTS.Common.Priority,System.State"
        try {
            $bugsResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems?ids=$idsStr&fields=$fields&api-version=7.0"
            foreach ($item in $bugsResult.value) {
                $assignedTo = if ($item.fields.PSObject.Properties["System.AssignedTo"]) { $item.fields."System.AssignedTo" } else { $null }
                $areaPath = if ($item.fields.PSObject.Properties["System.AreaPath"]) { $item.fields."System.AreaPath" } else { "" }
                $tags = if ($item.fields.PSObject.Properties["System.Tags"]) { $item.fields."System.Tags" } else { "" }

                $isAssigned = ($assignedTo -ne $null -and $assignedTo.ToString() -ne "")
                $hasCorrectArea = ($areaPath -match "Backend API")
                $isTagged = ($tags -match "needs-owner" -or $tags -match "needs.owner")

                if ($isAssigned) { $assignedCount++ }
                if ($hasCorrectArea) { $correctAreaCount++ }
                if ($isTagged) { $taggedCount++ }

                $bugDetails += @{
                    id = $item.id
                    title = $item.fields."System.Title"
                    assigned_to = if ($assignedTo) { $assignedTo.ToString() } else { "" }
                    area_path = $areaPath
                    tags = $tags
                    is_assigned = $isAssigned
                    has_correct_area = $hasCorrectArea
                    is_tagged = $isTagged
                }
            }
        } catch {
            Write-Host "WARNING: Could not query P1 bugs: $_"
        }
    }

    Write-Host "P1 bugs assigned: $assignedCount / $($p1BugIds.Count)"
    Write-Host "P1 bugs in correct area: $correctAreaCount / $($p1BugIds.Count)"
    Write-Host "P1 bugs tagged 'needs-owner': $taggedCount"

    # -----------------------------------------------------------------------
    # Step 2: Check for shared query named "Critical Bug Backlog"
    # -----------------------------------------------------------------------
    Write-Host "Checking for shared query..."
    $criticalQueryFound = $false
    $criticalQueryWiql = ""
    $criticalQueryId = $null

    try {
        # Recursively search shared queries
        $sharedQueries = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries/Shared%20Queries?`$depth=2&api-version=7.0"

        function Find-Query($node, $searchName) {
            if ($node.name -match $searchName) { return $node }
            if ($node.children) {
                foreach ($child in $node.children) {
                    $found = Find-Query $child $searchName
                    if ($found) { return $found }
                }
            }
            return $null
        }

        $foundQuery = Find-Query $sharedQueries "Critical Bug Backlog"
        if ($foundQuery) {
            $criticalQueryFound = $true
            $criticalQueryId = $foundQuery.id
            # Get full query to retrieve WIQL
            try {
                $fullQuery = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries/$($foundQuery.id)?api-version=7.0"
                $criticalQueryWiql = $fullQuery.wiql
            } catch { }
        }
    } catch {
        Write-Host "WARNING: Could not search shared queries: $_"
    }

    # Also try My Queries if not found in Shared
    if (-not $criticalQueryFound) {
        try {
            $myQueries = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries/My%20Queries?`$depth=3&api-version=7.0"
            $foundQuery = Find-Query $myQueries "Critical Bug Backlog"
            if ($foundQuery) {
                $criticalQueryFound = $true
                $criticalQueryId = $foundQuery.id
                $criticalQueryWiql = $foundQuery.wiql
            }
        } catch { }
    }

    # Also try flat WIQL query search
    if (-not $criticalQueryFound) {
        try {
            $allQueriesWiql = '{"query": "SELECT [System.Id] FROM WorkItemLinks WHERE Source.[System.Title] CONTAINS ''Critical Bug''"}'
            # Just search by listing all queries
            $allQueries = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/queries?`$depth=3&api-version=7.0"
            $foundQuery = Find-Query $allQueries "Critical Bug Backlog"
            if ($foundQuery) {
                $criticalQueryFound = $true
                $criticalQueryId = $foundQuery.id
            }
        } catch { }
    }

    Write-Host "Critical Bug Backlog query found: $criticalQueryFound (ID: $criticalQueryId)"

    # -----------------------------------------------------------------------
    # Step 3: Write result
    # -----------------------------------------------------------------------
    $result = @{
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        p1_bug_ids = $p1BugIds
        p1_bug_count = $p1BugIds.Count
        p1_bugs_assigned_count = $assignedCount
        p1_bugs_correct_area_count = $correctAreaCount
        p1_bugs_tagged_count = $taggedCount
        bug_details = $bugDetails
        critical_query_found = $criticalQueryFound
        critical_query_id = $criticalQueryId
        critical_query_wiql = $criticalQueryWiql
    }

    $resultPath = "C:\Users\Docker\task_results\work_item_triage_result.json"
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
