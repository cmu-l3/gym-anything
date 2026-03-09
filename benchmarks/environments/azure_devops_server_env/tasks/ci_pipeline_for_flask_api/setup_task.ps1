# Setup script for ci_pipeline_for_flask_api task.
# Deletes any existing pipeline definitions, ensures no azure-pipelines.yml
# exists in repo, then opens Edge to the Pipelines section.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_ci_pipeline.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up ci_pipeline_for_flask_api task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Clean-DesktopForTask
    $baseUrl = Wait-AzureDevOpsReady -TimeoutSeconds 120
    Write-Host "Azure DevOps URL: $baseUrl"

    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # -----------------------------------------------------------------------
    # Step 1: Delete all existing pipeline definitions
    # -----------------------------------------------------------------------
    Write-Host "Removing existing pipeline definitions..."
    try {
        $defs = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/build/definitions?api-version=7.0"
        foreach ($def in $defs.value) {
            try {
                Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/build/definitions/$($def.id)?api-version=7.0" -Method "DELETE" | Out-Null
                Write-Host "  Deleted pipeline: $($def.name) (ID: $($def.id))"
            } catch {
                Write-Host "  Could not delete pipeline $($def.id): $_"
            }
        }
        Write-Host "Pipeline cleanup done."
    } catch {
        Write-Host "No pipelines to remove or error: $_"
    }

    # -----------------------------------------------------------------------
    # Step 2: Ensure no azure-pipelines.yml in the main branch
    # (Delete it if it exists, so the agent creates it from scratch)
    # -----------------------------------------------------------------------
    Write-Host "Checking for azure-pipelines.yml in main branch..."
    try {
        $pipelineFile = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/git/repositories/TailwindTraders/items?path=/azure-pipelines.yml&versionDescriptor.version=main&api-version=7.0"
        # File exists — delete it via push
        Write-Host "  azure-pipelines.yml found, removing..."
        $refs = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/git/repositories/TailwindTraders/refs?filter=heads/main&api-version=7.0"
        $mainSha = $refs.value[0].objectId

        $deleteBody = @"
{
  "refUpdates": [{"name": "refs/heads/main", "oldObjectId": "$mainSha"}],
  "commits": [{
    "comment": "Remove CI pipeline file (task setup cleanup)",
    "changes": [{"changeType": "delete", "item": {"path": "/azure-pipelines.yml"}}]
  }]
}
"@
        Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/git/repositories/TailwindTraders/pushes?api-version=7.0" -Method "POST" -Body $deleteBody | Out-Null
        Write-Host "  azure-pipelines.yml removed from main."
    } catch {
        Write-Host "  azure-pipelines.yml not present or error: $_"
    }

    # -----------------------------------------------------------------------
    # Step 3: Record baseline (no pipelines)
    # -----------------------------------------------------------------------
    $baseline = @{
        pipeline_count_before = 0
        has_pipeline_yaml = $false
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $baseline | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Users\Docker\task_results\ci_pipeline_baseline.json" -Encoding UTF8 -Force
    Write-Host "Baseline saved."

    # -----------------------------------------------------------------------
    # Step 4: Open Edge to Pipelines section
    # -----------------------------------------------------------------------
    $pipelinesUrl = "$baseUrl/TailwindTraders/_build"
    Write-Host "Opening Pipelines at: $pipelinesUrl"
    Launch-EdgeInteractive -Url $pipelinesUrl -WaitSeconds 12

    Write-Host "=== ci_pipeline_for_flask_api setup complete. No pipelines exist. ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
