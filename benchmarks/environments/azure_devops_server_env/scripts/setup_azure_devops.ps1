Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Azure DevOps Server environment.
# This script runs after Windows boots (post_start hook).
# Creates project, seeds work items, initializes Git repo.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Azure DevOps Server environment ==="

    # ---- Phase 1: Detect Azure DevOps URL ----
    Write-Host ""
    Write-Host "--- Phase 1: Detecting Azure DevOps URL ---"

    $baseUrl = $null
    $candidateUrls = @(
        "http://localhost/DefaultCollection",
        "http://localhost:8080/tfs/DefaultCollection",
        "http://localhost:80/DefaultCollection"
    )

    $maxWait = 180
    $elapsed = 0
    while ($elapsed -lt $maxWait) {
        foreach ($url in $candidateUrls) {
            try {
                $response = Invoke-WebRequest -Uri "$url/_apis/projects?api-version=7.1" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    $baseUrl = $url
                    Write-Host "Azure DevOps Server responding at: $baseUrl"
                    break
                }
            } catch {}
        }
        if ($baseUrl) { break }
        Start-Sleep -Seconds 10
        $elapsed += 10
        Write-Host "  Waiting for Azure DevOps... ($elapsed/$maxWait seconds)"
    }

    if (-not $baseUrl) {
        throw "Azure DevOps Server not responding after ${maxWait}s. Check installation logs."
    }

    # Save base URL for tasks
    $baseUrl | Out-File -FilePath "C:\Users\Docker\azure_devops_url.txt" -Force

    # ---- Phase 2: Configure Edge Browser ----
    Write-Host ""
    Write-Host "--- Phase 2: Configuring Edge Browser ---"

    # Suppress Edge first-run experience
    $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePath)) {
        New-Item -Path $edgePath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePath -Name "HideFirstRunExperience" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $edgePath -Name "AutoImportAtFirstRun" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path $edgePath -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $edgePath -Name "HideRestoreDialogEnabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $edgePath -Name "RestoreOnStartup" -Value 4 -Type DWord -Force

    # Enable automatic NTLM auth for localhost (critical for Azure DevOps)
    Set-ItemProperty -Path $edgePath -Name "AuthServerAllowlist" -Value "localhost" -Type String -Force
    Set-ItemProperty -Path $edgePath -Name "AuthNegotiateDelegateAllowlist" -Value "localhost" -Type String -Force

    # Also configure IE zone for NTLM
    $zonePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\localhost"
    if (-not (Test-Path $zonePath)) {
        New-Item -Path $zonePath -Force | Out-Null
    }
    Set-ItemProperty -Path $zonePath -Name "http" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $zonePath -Name "https" -Value 1 -Type DWord -Force

    Write-Host "Edge browser configured for automatic NTLM authentication."

    # Disable and uninstall OneDrive
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $onedrivePolicyPath)) {
        New-Item -Path $onedrivePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    # Uninstall OneDrive completely
    $odSetup = "C:\Windows\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $odSetup)) { $odSetup = "C:\Windows\System32\OneDriveSetup.exe" }
    if (Test-Path $odSetup) {
        Start-Process $odSetup -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
        Write-Host "OneDrive uninstalled."
    }

    # Suppress ALL Windows toast notifications (prevents "Turn On Windows Backup" and similar)
    # Disable toast notifications globally
    $wpnPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $wpnPath)) { New-Item -Path $wpnPath -Force | Out-Null }
    Set-ItemProperty -Path $wpnPath -Name "ToastEnabled" -Value 0 -Type DWord -Force
    # Disable Windows Backup reminders specifically
    $backupNotifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.BackupReminder"
    if (-not (Test-Path $backupNotifPath)) { New-Item -Path $backupNotifPath -Force | Out-Null }
    Set-ItemProperty -Path $backupNotifPath -Name "Enabled" -Value 0 -Type DWord -Force
    # Disable cloud content / suggested content
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cloudPath)) { New-Item -Path $cloudPath -Force | Out-Null }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $cloudPath -Name "DisableSoftLanding" -Value 1 -Type DWord -Force
    # Disable action center notifications
    $explorerPolicyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $explorerPolicyPath)) { New-Item -Path $explorerPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $explorerPolicyPath -Name "DisableNotificationCenter" -Value 1 -Type DWord -Force
    # Disable OneDrive-specific notifications
    $odNotifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop"
    if (-not (Test-Path $odNotifPath)) { New-Item -Path $odNotifPath -Force | Out-Null }
    Set-ItemProperty -Path $odNotifPath -Name "Enabled" -Value 0 -Type DWord -Force
    Write-Host "All toast notifications suppressed."

    # ---- Phase 3: Create Project ----
    Write-Host ""
    Write-Host "--- Phase 3: Creating Demo Project ---"

    # Check if project already exists
    $projectsResponse = Invoke-RestMethod -Uri "$baseUrl/_apis/projects?api-version=7.1" -UseDefaultCredentials -ContentType "application/json"
    $existingProject = $projectsResponse.value | Where-Object { $_.name -eq "TailwindTraders" }

    if ($existingProject) {
        Write-Host "Project 'TailwindTraders' already exists."
        $projectId = $existingProject.id
    } else {
        Write-Host "Creating project 'TailwindTraders'..."
        $projectBody = @{
            name = "TailwindTraders"
            description = "Tailwind Traders inventory management platform - full-stack web application with REST API, database, and React frontend"
            capabilities = @{
                versioncontrol = @{ sourceControlType = "Git" }
                processTemplate = @{ templateTypeId = "adcc42ab-9882-485e-a3ed-7678f01f66bc" }
            }
        } | ConvertTo-Json -Depth 5

        $opResponse = Invoke-RestMethod -Uri "$baseUrl/_apis/projects?api-version=7.1" -UseDefaultCredentials -Method Post -Body $projectBody -ContentType "application/json"

        # Wait for project creation to complete
        Write-Host "Project creation queued. Waiting for completion..."
        $opUrl = $opResponse.url
        $maxProjectWait = 120
        $projElapsed = 0
        while ($projElapsed -lt $maxProjectWait) {
            Start-Sleep -Seconds 5
            $projElapsed += 5
            try {
                $opStatus = Invoke-RestMethod -Uri $opUrl -UseDefaultCredentials -ContentType "application/json"
                if ($opStatus.status -eq "succeeded") {
                    Write-Host "Project created successfully."
                    break
                } elseif ($opStatus.status -eq "failed") {
                    Write-Host "WARNING: Project creation failed: $($opStatus.resultMessage)"
                    break
                }
                Write-Host "  Project creation status: $($opStatus.status) ($projElapsed/$maxProjectWait s)"
            } catch {
                Write-Host "  Checking status... ($projElapsed/$maxProjectWait s)"
            }
        }

        # Get project ID
        Start-Sleep -Seconds 5
        $projectsResponse = Invoke-RestMethod -Uri "$baseUrl/_apis/projects?api-version=7.1" -UseDefaultCredentials -ContentType "application/json"
        $project = $projectsResponse.value | Where-Object { $_.name -eq "TailwindTraders" }
        if ($project) {
            $projectId = $project.id
            Write-Host "Project ID: $projectId"
        } else {
            throw "Failed to find created project 'TailwindTraders'"
        }
    }

    # ---- Phase 4: Create Iterations (Sprints) ----
    Write-Host ""
    Write-Host "--- Phase 4: Creating Sprints ---"

    $sprints = @(
        @{ name = "Sprint 1"; startDate = "2026-01-06T00:00:00Z"; finishDate = "2026-01-19T00:00:00Z" },
        @{ name = "Sprint 2"; startDate = "2026-01-20T00:00:00Z"; finishDate = "2026-02-02T00:00:00Z" },
        @{ name = "Sprint 3"; startDate = "2026-02-03T00:00:00Z"; finishDate = "2026-02-16T00:00:00Z" },
        @{ name = "Sprint 4"; startDate = "2026-02-17T00:00:00Z"; finishDate = "2026-03-02T00:00:00Z" }
    )

    foreach ($sprint in $sprints) {
        try {
            $sprintBody = @{
                name = $sprint.name
                attributes = @{
                    startDate = $sprint.startDate
                    finishDate = $sprint.finishDate
                }
            } | ConvertTo-Json -Depth 5

            Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/wit/classificationnodes/iterations?api-version=7.1" -UseDefaultCredentials -Method Post -Body $sprintBody -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Created iteration: $($sprint.name)"
        } catch {
            Write-Host "Iteration '$($sprint.name)' may already exist: $($_.Exception.Message)"
        }
    }

    # Add sprints to team iterations
    Write-Host "Assigning sprints to team iterations..."
    try {
        $classNodes = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/wit/classificationnodes/iterations?`$depth=2&api-version=7.1" -UseDefaultCredentials
        foreach ($sprintName in @("Sprint 1", "Sprint 2", "Sprint 3", "Sprint 4")) {
            $node = $classNodes.children | Where-Object { $_.name -eq $sprintName }
            if ($node) {
                try {
                    $addBody = @{ id = $node.identifier } | ConvertTo-Json
                    Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/work/teamsettings/iterations?api-version=7.1" -UseDefaultCredentials -Method Post -Body $addBody -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "  Added $sprintName to team."
                } catch {
                    Write-Host "  $sprintName already in team or error."
                }
            }
        }
    } catch {
        Write-Host "WARNING: Failed to assign sprints to team: $($_.Exception.Message)"
    }

    # Remove default Iteration 1/2/3 from team iterations (clutter)
    Write-Host "Removing default iterations from team..."
    try {
        $teamIters = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/work/teamsettings/iterations?api-version=7.1" -UseDefaultCredentials
        foreach ($iter in $teamIters.value) {
            if ($iter.name -match "^Iteration \d+$") {
                try {
                    Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/work/teamsettings/iterations/$($iter.id)?api-version=7.1" -UseDefaultCredentials -Method Delete | Out-Null
                    Write-Host "  Removed $($iter.name) from team iterations."
                } catch {
                    Write-Host "  Could not remove $($iter.name): $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Host "WARNING: Failed to clean up default iterations: $($_.Exception.Message)"
    }

    # ---- Phase 5: Seed Work Items ----
    Write-Host ""
    Write-Host "--- Phase 5: Seeding Work Items ---"

    # Check if work items already exist (idempotency)
    $existingWiCount = 0
    try {
        $wiqlBody = @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = 'TailwindTraders'" } | ConvertTo-Json
        $wiqlResult = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/wit/wiql?api-version=7.1" -UseDefaultCredentials -Method Post -Body $wiqlBody -ContentType "application/json"
        $existingWiCount = $wiqlResult.workItems.Count
    } catch {}

    $workItemsFile = "C:\workspace\data\work_items.json"
    if ($existingWiCount -gt 0) {
        Write-Host "Work items already exist ($existingWiCount found). Skipping seeding."
    } elseif (Test-Path $workItemsFile) {
        $workItems = Get-Content $workItemsFile -Raw | ConvertFrom-Json

        foreach ($wi in $workItems) {
            try {
                $fields = @()
                $fields += @{ op = "add"; path = "/fields/System.Title"; value = $wi.title }

                if (($wi.PSObject.Properties.Name -contains 'description') -and $wi.description) {
                    $descField = if ($wi.type -eq "Bug") { "/fields/Microsoft.VSTS.TCM.ReproSteps" } else { "/fields/System.Description" }
                    $fields += @{ op = "add"; path = $descField; value = $wi.description }
                }
                # Note: Cannot set state to non-default value on creation; always create as "New"
                if (($wi.PSObject.Properties.Name -contains 'priority') -and $wi.priority) {
                    $fields += @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority"; value = [int]$wi.priority }
                }
                if (($wi.PSObject.Properties.Name -contains 'areaPath') -and $wi.areaPath) {
                    $fields += @{ op = "add"; path = "/fields/System.AreaPath"; value = $wi.areaPath }
                }
                if (($wi.PSObject.Properties.Name -contains 'iterationPath') -and $wi.iterationPath) {
                    $fields += @{ op = "add"; path = "/fields/System.IterationPath"; value = $wi.iterationPath }
                }
                if ($wi.type -eq "User Story" -and ($wi.PSObject.Properties.Name -contains 'acceptanceCriteria') -and $wi.acceptanceCriteria) {
                    $fields += @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"; value = $wi.acceptanceCriteria }
                }
                if (($wi.PSObject.Properties.Name -contains 'tags') -and $wi.tags) {
                    $fields += @{ op = "add"; path = "/fields/System.Tags"; value = $wi.tags }
                }

                $body = $fields | ConvertTo-Json -Depth 5
                $wiType = [Uri]::EscapeDataString("`$$($wi.type)")
                $response = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/wit/workitems/$($wiType)?api-version=7.1" -UseDefaultCredentials -Method Post -Body $body -ContentType "application/json-patch+json"
                Write-Host "Created $($wi.type): $($wi.title) (ID: $($response.id))"
            } catch {
                Write-Host "WARNING: Failed to create work item '$($wi.title)': $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "WARNING: Work items file not found at: $workItemsFile"
    }

    # ---- Phase 6: Initialize Git Repository ----
    Write-Host ""
    Write-Host "--- Phase 6: Initializing Git Repository ---"

    # Get the default repo
    try {
        $reposResponse = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories?api-version=7.1" -UseDefaultCredentials -ContentType "application/json"
        $defaultRepo = $reposResponse.value | Where-Object { $_.name -eq "TailwindTraders" } | Select-Object -First 1

        if ($defaultRepo) {
            $repoId = $defaultRepo.id
            Write-Host "Default repo ID: $repoId"

            # Check if repo has any refs (already initialized)
            $refsResponse = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/$repoId/refs?api-version=7.1" -UseDefaultCredentials -ContentType "application/json"

            if ($refsResponse.count -eq 0) {
                Write-Host "Initializing repository with project files..."

                # Read specific repo files to avoid size issues
                $repoSourceDir = "C:\workspace\data\repo_files"
                $filesToPush = @(
                    "app.py", "models.py", "routes.py", "config.py",
                    "requirements.txt", "Dockerfile", ".gitignore", "README.md"
                )

                $repoFiles = @()
                foreach ($fileName in $filesToPush) {
                    $fullPath = Join-Path $repoSourceDir $fileName
                    if (Test-Path $fullPath) {
                        $content = [System.IO.File]::ReadAllText($fullPath)
                        $repoFiles += @{
                            changeType = "add"
                            item = @{ path = "/$fileName" }
                            newContent = @{
                                content = $content
                                contentType = "rawtext"
                            }
                        }
                    }
                }

                # Also add test file
                $testPath = Join-Path $repoSourceDir "tests\test_app.py"
                if (Test-Path $testPath) {
                    $content = [System.IO.File]::ReadAllText($testPath)
                    $repoFiles += @{
                        changeType = "add"
                        item = @{ path = "/tests/test_app.py" }
                        newContent = @{
                            content = $content
                            contentType = "rawtext"
                        }
                    }
                }

                if ($repoFiles.Count -gt 0) {
                    $pushBody = @{
                        refUpdates = @(
                            @{
                                name = "refs/heads/main"
                                oldObjectId = "0000000000000000000000000000000000000000"
                            }
                        )
                        commits = @(
                            @{
                                comment = "Initial commit - Tailwind Traders Inventory API"
                                changes = $repoFiles
                            }
                        )
                    } | ConvertTo-Json -Depth 6 -Compress

                    $pushResponse = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/$repoId/pushes?api-version=7.1" -UseDefaultCredentials -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($pushBody)) -ContentType "application/json"
                    Write-Host "Repository initialized with $($repoFiles.Count) files."

                    # Create a feature branch from main
                    Write-Host "Creating feature branch..."
                    $mainRef = Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/$repoId/refs?filter=heads/main&api-version=7.1" -UseDefaultCredentials -ContentType "application/json"
                    $mainObjectId = $mainRef.value[0].objectId

                    $branchItem = @{
                        name = "refs/heads/feature/add-search-endpoint"
                        oldObjectId = "0000000000000000000000000000000000000000"
                        newObjectId = $mainObjectId
                    } | ConvertTo-Json -Depth 5
                    $branchBody = "[$branchItem]"

                    Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/$repoId/refs?api-version=7.1" -UseDefaultCredentials -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($branchBody)) -ContentType "application/json" | Out-Null
                    Write-Host "Feature branch 'feature/add-search-endpoint' created."

                    # Add a commit to the feature branch
                    $featurePushBody = @{
                        refUpdates = @(
                            @{
                                name = "refs/heads/feature/add-search-endpoint"
                                oldObjectId = $mainObjectId
                            }
                        )
                        commits = @(
                            @{
                                comment = "Add product search endpoint with filtering support"
                                changes = @(
                                    @{
                                        changeType = "add"
                                        item = @{ path = "/search.py" }
                                        newContent = @{
                                            content = @"
from flask import Blueprint, request, jsonify
from models import db, Product

search_bp = Blueprint('search', __name__)


@search_bp.route('/api/v1/products/search', methods=['GET'])
def search_products():
    query = request.args.get('q', '')
    category = request.args.get('category', None)
    min_price = request.args.get('min_price', type=float)
    max_price = request.args.get('max_price', type=float)
    in_stock = request.args.get('in_stock', type=bool)

    filters = []
    if query:
        filters.append(Product.name.ilike(f'%{query}%'))
    if category:
        filters.append(Product.category == category)
    if min_price is not None:
        filters.append(Product.price >= min_price)
    if max_price is not None:
        filters.append(Product.price <= max_price)
    if in_stock:
        filters.append(Product.stock_quantity > 0)

    results = Product.query.filter(*filters).limit(50).all()
    return jsonify([p.to_dict() for p in results])
"@
                                            contentType = "rawtext"
                                        }
                                    }
                                )
                            }
                        )
                    } | ConvertTo-Json -Depth 6 -Compress

                    Invoke-RestMethod -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/$repoId/pushes?api-version=7.1" -UseDefaultCredentials -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($featurePushBody)) -ContentType "application/json" | Out-Null
                    Write-Host "Feature branch committed with search endpoint code."
                } else {
                    Write-Host "WARNING: No repo files found at: $repoSourceDir"
                }
            } else {
                Write-Host "Repository already initialized ($($refsResponse.count) refs)."
            }
        } else {
            Write-Host "WARNING: Default repository not found."
        }
    } catch {
        Write-Host "WARNING: Git repository setup failed: $($_.Exception.Message)"
    }

    # ---- Phase 7: Warm-up Edge Browser ----
    Write-Host ""
    Write-Host "--- Phase 7: Warming Up Edge Browser ---"

    # Launch Edge to Azure DevOps to trigger first-run auth
    $edgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgeExe)) {
        $edgeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    }

    if (Test-Path $edgeExe) {
        $warmupScript = "C:\Windows\Temp\warmup_edge.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$edgeExe`" --no-first-run --disable-sync --no-default-browser-check `"$baseUrl/TailwindTraders`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $futureTime = (Get-Date).AddMinutes(2).ToString("HH:mm")
        schtasks /Create /TN "WarmupEdge_GA" /TR "cmd /c $warmupScript" /SC ONCE /ST $futureTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupEdge_GA" 2>$null
        Start-Sleep -Seconds 15
        # Kill Edge after warm-up
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupEdge_GA" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "Edge browser warm-up complete."
    } else {
        Write-Host "WARNING: Edge browser not found."
    }

    # Minimize terminal windows
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }

    Write-Host ""
    Write-Host "=== Azure DevOps Server environment setup complete ==="
    Write-Host "Base URL: $baseUrl"
    Write-Host "Project: TailwindTraders"
    Write-Host "Auth: NTLM (automatic with Docker user)"

} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
