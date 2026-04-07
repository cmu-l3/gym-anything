# Export script for release_notes_preparation task.
# Queries the current state of:
#   - release/v1.5.0 branch existence and config.py content
#   - Sprint 1 P1 bug tags and comments
#   - Wiki page "Release v1.5.0" existence and content
# Writes result JSON for verifier.py.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_release_notes_preparation.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting release_notes_preparation result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    $baseUrl = Get-AzureDevOpsUrl
    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    $repoApi = "/TailwindTraders/_apis/git/repositories/TailwindTraders"

    # -----------------------------------------------------------------------
    # Step 1: Load baseline
    # -----------------------------------------------------------------------
    $baselinePath = "C:\Users\Docker\task_results\release_notes_preparation_baseline.json"
    $baseline = @{ sprint1_items = @(); timestamp = "" }
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
        } catch {
            Write-Host "WARNING: Could not parse baseline: $_"
        }
    }

    # -----------------------------------------------------------------------
    # Step 2: Check release/v1.5.0 branch existence
    # -----------------------------------------------------------------------
    Write-Host "Checking release/v1.5.0 branch..."
    $branchExists = $false
    try {
        $refs = Invoke-AzDevOpsApi -Path "$repoApi/refs?filter=heads/release/v1.5.0&api-version=7.0"
        if ($refs.value.Count -gt 0) {
            $branchExists = $true
            Write-Host "  Branch release/v1.5.0 exists."
        } else {
            Write-Host "  Branch release/v1.5.0 NOT found."
        }
    } catch {
        Write-Host "  Error checking branch: $_"
    }

    # -----------------------------------------------------------------------
    # Step 3: Get config.py content from release branch
    # -----------------------------------------------------------------------
    Write-Host "Checking config.py on release branch..."
    $configContent = ""
    $configHasVersion = $false
    $configHasProductionDefault = $false
    if ($branchExists) {
        try {
            $fileResult = Invoke-AzDevOpsApi -Path "$repoApi/items?path=/config.py&versionDescriptor.version=release/v1.5.0&versionDescriptor.versionType=branch&api-version=7.0"
            # The API returns the file content directly as a string
            $configContent = $fileResult
            if ($configContent -is [string]) {
                $configHasVersion = $configContent -match "VERSION\s*=\s*['""]1\.5\.0['""]"
                $configHasProductionDefault = $configContent -match "['""]default['""]\s*:\s*ProductionConfig"
                Write-Host "  config.py retrieved. VERSION=1.5.0: $configHasVersion, default=ProductionConfig: $configHasProductionDefault"
            } else {
                Write-Host "  config.py response was not a string, trying to convert..."
                $configContent = $fileResult | Out-String
                $configHasVersion = $configContent -match "VERSION\s*=\s*['""]1\.5\.0['""]"
                $configHasProductionDefault = $configContent -match "['""]default['""]\s*:\s*ProductionConfig"
            }
        } catch {
            Write-Host "  Could not retrieve config.py from release branch: $_"
        }
    }

    # -----------------------------------------------------------------------
    # Step 4: Check Sprint 1 P1 bug tags and comments
    # -----------------------------------------------------------------------
    Write-Host "Checking Sprint 1 P1 bug states..."
    $bugResults = @()

    $wiqlBody = '{"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.IterationPath] UNDER ''TailwindTraders\\Sprint 1'' AND [System.WorkItemType] = ''Bug'' AND [Microsoft.VSTS.Common.Priority] = 1 ORDER BY [System.Id]"}'
    try {
        $wiqlResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $wiqlBody
        $bugIds = @($wiqlResult.workItems | Select-Object -ExpandProperty id)

        foreach ($bugId in $bugIds) {
            $bug = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($bugId)?fields=System.Id,System.Title,System.State,System.Tags&api-version=7.0"
            $title = $bug.fields."System.Title"
            $state = $bug.fields."System.State"
            $tags = if ($bug.fields."System.Tags") { $bug.fields."System.Tags" } else { "" }
            $hasReleaseBlockerTag = $tags -match "release-blocker"

            # Check for comments
            $hasReleaseComment = $false
            try {
                $comments = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workItems/$($bugId)/comments?api-version=7.0-preview.3"
                foreach ($comment in $comments.comments) {
                    if ($comment.text -match "(?i)(v1\.5\.0|release|blocker|shipping)") {
                        $hasReleaseComment = $true
                        break
                    }
                }
            } catch {
                Write-Host "  Could not fetch comments for bug #$bugId : $_"
            }

            $bugResults += @{
                id = $bugId
                title = $title
                state = $state
                tags = $tags
                has_release_blocker_tag = $hasReleaseBlockerTag
                has_release_comment = $hasReleaseComment
            }
            Write-Host "  Bug #$bugId '$title' State=$state Tags='$tags' ReleaseBlockerTag=$hasReleaseBlockerTag ReleaseComment=$hasReleaseComment"
        }
    } catch {
        Write-Host "  Error querying P1 bugs: $_"
    }

    # -----------------------------------------------------------------------
    # Step 5: Check all Sprint 1 work item tags (for false positive check)
    # -----------------------------------------------------------------------
    Write-Host "Checking for false positive release-blocker tags..."
    $falsePositiveTags = @()
    try {
        $allWiqlBody = '{"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = ''TailwindTraders'' AND [System.IterationPath] UNDER ''TailwindTraders\\Sprint 1'' ORDER BY [System.Id]"}'
        $allResult = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/wiql?api-version=7.0" -Method "POST" -Body $allWiqlBody
        $allIds = @($allResult.workItems | Select-Object -ExpandProperty id)

        foreach ($itemId in $allIds) {
            $item = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wit/workitems/$($itemId)?fields=System.Id,System.Title,System.State,System.Tags,System.WorkItemType,Microsoft.VSTS.Common.Priority&api-version=7.0"
            $tags = if ($item.fields."System.Tags") { $item.fields."System.Tags" } else { "" }
            $state = $item.fields."System.State"
            $priority = $item.fields."Microsoft.VSTS.Common.Priority"
            $wiType = $item.fields."System.WorkItemType"

            # A false positive is: has release-blocker tag but should NOT
            # Should NOT have tag if: not a Bug, or not P1, or state is Resolved/Closed
            if ($tags -match "release-blocker") {
                $shouldHaveTag = ($wiType -eq "Bug") -and ($priority -eq 1) -and ($state -notin @("Resolved", "Closed"))
                if (-not $shouldHaveTag) {
                    $falsePositiveTags += @{
                        id = $itemId
                        title = $item.fields."System.Title"
                        type = $wiType
                        priority = $priority
                        state = $state
                    }
                    Write-Host "  FALSE POSITIVE: #$itemId '$($item.fields.'System.Title')' has release-blocker but shouldn't"
                }
            }
        }
    } catch {
        Write-Host "  Error checking false positives: $_"
    }

    # -----------------------------------------------------------------------
    # Step 6: Check wiki page
    # -----------------------------------------------------------------------
    Write-Host "Checking wiki page 'Release v1.5.0'..."
    $wikiPageExists = $false
    $wikiContent = ""
    $wikiHasCompletedSection = $false
    $wikiHasKnownIssuesSection = $false
    $wikiHasReleaseDateSection = $false
    $wikiCompletedItemTitles = @()
    $wikiKnownIssueTitles = @()

    try {
        $wikis = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis?api-version=7.0"
        foreach ($wiki in $wikis.value) {
            try {
                $page = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/wiki/wikis/$($wiki.id)/pages?path=/Release%20v1.5.0&includeContent=true&api-version=7.0"
                if ($page) {
                    $wikiPageExists = $true
                    $wikiContent = if ($page.content) { $page.content } else { "" }
                    Write-Host "  Wiki page found in '$($wiki.name)'. Content length: $($wikiContent.Length)"

                    # Check sections
                    $wikiHasCompletedSection = $wikiContent -match "(?i)##\s*Completed\s*Items"
                    $wikiHasKnownIssuesSection = $wikiContent -match "(?i)##\s*Known\s*Issues"
                    $wikiHasReleaseDateSection = $wikiContent -match "(?i)March\s*22,?\s*2026"

                    # Check for completed item titles
                    $completedTitles = @(
                        "Implement product inventory search with full-text filtering",
                        "Design REST API rate limiting and authentication middleware",
                        "API returns 500 error when filtering products with special characters in category name",
                        "Set up PostgreSQL database migration scripts for v2.0 schema changes",
                        "Configure CI/CD pipeline for automated testing and staging deployment"
                    )
                    foreach ($ct in $completedTitles) {
                        # Check for partial title match (at least first 20 chars)
                        $shortTitle = $ct.Substring(0, [Math]::Min(20, $ct.Length))
                        if ($wikiContent -match [regex]::Escape($shortTitle)) {
                            $wikiCompletedItemTitles += $ct
                        }
                    }

                    # Check for known issue (blocker) titles
                    $blockerTitles = @(
                        "Product price calculation returns incorrect values for bulk discount tiers",
                        "Inventory count becomes negative after concurrent stock deduction requests"
                    )
                    foreach ($bt in $blockerTitles) {
                        $shortTitle = $bt.Substring(0, [Math]::Min(20, $bt.Length))
                        if ($wikiContent -match [regex]::Escape($shortTitle)) {
                            $wikiKnownIssueTitles += $bt
                        }
                    }

                    break  # Found the page, no need to check other wikis
                }
            } catch {
                # Page not found in this wiki, try next
            }
        }
    } catch {
        Write-Host "  Error checking wiki: $_"
    }

    if (-not $wikiPageExists) {
        Write-Host "  Wiki page 'Release v1.5.0' NOT found."
    }

    # -----------------------------------------------------------------------
    # Step 7: Write result JSON
    # -----------------------------------------------------------------------
    $result = @{
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        baseline_timestamp = $baseline.timestamp

        # Branch and config
        branch_exists = $branchExists
        config_has_version = $configHasVersion
        config_has_production_default = $configHasProductionDefault
        config_content_snippet = if ($configContent -and $configContent.Length -gt 500) { $configContent.Substring(0, 500) } else { if ($configContent) { $configContent } else { "" } }

        # Bug audit
        p1_bugs = $bugResults
        p1_bug_count = @($bugResults).Count
        bugs_with_release_blocker_tag = @($bugResults | Where-Object { $_.has_release_blocker_tag }).Count
        bugs_with_release_comment = @($bugResults | Where-Object { $_.has_release_comment }).Count
        false_positive_tags = $falsePositiveTags
        false_positive_count = @($falsePositiveTags).Count

        # Wiki
        wiki_page_exists = $wikiPageExists
        wiki_content = if ($wikiContent) { $wikiContent } else { "" }
        wiki_has_completed_section = $wikiHasCompletedSection
        wiki_has_known_issues_section = $wikiHasKnownIssuesSection
        wiki_has_release_date = $wikiHasReleaseDateSection
        wiki_completed_item_titles_found = $wikiCompletedItemTitles
        wiki_completed_items_count = @($wikiCompletedItemTitles).Count
        wiki_known_issue_titles_found = $wikiKnownIssueTitles
        wiki_known_issues_count = @($wikiKnownIssueTitles).Count
    }

    $resultPath = "C:\Users\Docker\task_results\release_notes_preparation_result.json"
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
