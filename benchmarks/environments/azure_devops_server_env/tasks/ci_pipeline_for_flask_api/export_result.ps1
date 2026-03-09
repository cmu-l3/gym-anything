# Export script for ci_pipeline_for_flask_api task.
# Queries pipeline definitions, retrieves YAML content, checks for required elements.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_ci_pipeline.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting ci_pipeline_for_flask_api result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    New-Item -ItemType Directory -Path "C:\Users\Docker\task_results" -Force | Out-Null

    # -----------------------------------------------------------------------
    # Step 1: Get all pipeline definitions
    # -----------------------------------------------------------------------
    Write-Host "Querying pipeline definitions..."
    $pipelines = @()
    $pipelineCount = 0
    $hasCiTrigger = $false
    $hasMainTrigger = $false
    $hasPrTrigger = $false
    $hasPythonSetup = $false
    $hasDependencyInstall = $false
    $hasTestExecution = $false
    $combinedYaml = ""

    try {
        $defs = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/build/definitions?api-version=7.0"
        $pipelineCount = $defs.count

        foreach ($def in $defs.value) {
            $defId = $def.id
            $defName = $def.name

            # Get full definition (includes YAML content for YAML pipelines)
            try {
                $fullDef = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/build/definitions/$($defId)?api-version=7.0"

                $pipelineInfo = @{
                    id = $defId
                    name = $defName
                    type = $fullDef.type
                    process_type = if ($fullDef.process) { $fullDef.process.type } else { $null }
                    yaml_filename = if ($fullDef.process) { $fullDef.process.yamlFilename } else { $null }
                    triggers = @()
                }

                # Check triggers from definition
                if ($fullDef.triggers) {
                    foreach ($trigger in $fullDef.triggers) {
                        $pipelineInfo.triggers += $trigger.triggerType
                        if ($trigger.triggerType -eq "continuousIntegration" -or $trigger.triggerType -eq "schedule") {
                            $hasCiTrigger = $true
                            if ($trigger.branchFilters) {
                                $branchStr = ($trigger.branchFilters | ConvertTo-Json)
                                if ($branchStr -match "main") { $hasMainTrigger = $true }
                            }
                        }
                        if ($trigger.triggerType -eq "pullRequest") { $hasPrTrigger = $true }
                    }
                }

                $pipelines += $pipelineInfo

                # Try to get the YAML file content from the repo
                $yamlFile = if ($fullDef.process) { $fullDef.process.yamlFilename } else { "azure-pipelines.yml" }
                if (-not $yamlFile) { $yamlFile = "azure-pipelines.yml" }

                try {
                    $yamlItem = Invoke-AzDevOpsApi -Path "/TailwindTraders/_apis/git/repositories/TailwindTraders/items?path=/$($yamlFile)&versionDescriptor.version=main&api-version=7.0"
                    $yamlContent = $yamlItem.content
                    if (-not $yamlContent) {
                        # Download the content
                        $baseUrl = Get-AzureDevOpsUrl
                        $rawResponse = Invoke-WebRequest -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/TailwindTraders/items?path=/$($yamlFile)&versionDescriptor.version=main&`$format=text&api-version=7.0" -UseDefaultCredentials -UseBasicParsing
                        $yamlContent = $rawResponse.Content
                    }
                    if ($yamlContent) {
                        $combinedYaml += $yamlContent
                        Write-Host "  Retrieved YAML from $yamlFile ($($yamlContent.Length) chars)"
                    }
                } catch {
                    Write-Host "  Could not retrieve YAML file $yamlFile : $_"
                }

            } catch {
                Write-Host "  Could not get full definition for #$defId : $_"
            }
        }
    } catch {
        Write-Host "WARNING: Could not query pipeline definitions: $_"
    }

    # -----------------------------------------------------------------------
    # Step 2: Also check repo for any YAML pipeline files
    # -----------------------------------------------------------------------
    $yamlFiles = @("azure-pipelines.yml", ".azure/pipelines/ci.yml", "pipeline.yml", "ci.yml")
    foreach ($yf in $yamlFiles) {
        try {
            $baseUrl = Get-AzureDevOpsUrl
            $rawResponse = Invoke-WebRequest -Uri "$baseUrl/TailwindTraders/_apis/git/repositories/TailwindTraders/items?path=/$yf&versionDescriptor.version=main&`$format=text&api-version=7.0" -UseDefaultCredentials -UseBasicParsing -ErrorAction Stop
            if ($rawResponse.StatusCode -eq 200) {
                $combinedYaml += $rawResponse.Content
                Write-Host "Found YAML file: $yf"
            }
        } catch { }
    }

    # -----------------------------------------------------------------------
    # Step 3: Analyze combined YAML content
    # -----------------------------------------------------------------------
    if ($combinedYaml) {
        $yamlLower = $combinedYaml.ToLower()

        # Check for triggers
        if ($yamlLower -match "trigger") { $hasCiTrigger = $true }
        if ($yamlLower -match "main") { $hasMainTrigger = $true }
        if ($yamlLower -match "^pr:|^\s+pr:|\bpull.?request") { $hasPrTrigger = $true }

        # Check for Python setup
        if ($yamlLower -match "python|usepythonversion|python_version") { $hasPythonSetup = $true }

        # Check for dependency installation
        if ($yamlLower -match "pip install|requirements\.txt|pip3 install") { $hasDependencyInstall = $true }

        # Check for test execution
        if ($yamlLower -match "pytest|python -m pytest|unittest|test") { $hasTestExecution = $true }
    }

    Write-Host "Pipeline count: $pipelineCount"
    Write-Host "Has CI trigger: $hasCiTrigger | main: $hasMainTrigger | PR: $hasPrTrigger"
    Write-Host "Has Python: $hasPythonSetup | Deps: $hasDependencyInstall | Tests: $hasTestExecution"

    # -----------------------------------------------------------------------
    # Step 4: Write result
    # -----------------------------------------------------------------------
    $result = @{
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        pipeline_count = $pipelineCount
        pipelines = $pipelines
        yaml_content_found = ($combinedYaml.Length -gt 0)
        yaml_content_length = $combinedYaml.Length
        has_ci_trigger = $hasCiTrigger
        has_main_trigger = $hasMainTrigger
        has_pr_trigger = $hasPrTrigger
        has_python_setup = $hasPythonSetup
        has_dependency_install = $hasDependencyInstall
        has_test_execution = $hasTestExecution
        combined_yaml_snippet = if ($combinedYaml.Length -gt 2000) { $combinedYaml.Substring(0, 2000) } else { $combinedYaml }
    }

    $resultPath = "C:\Users\Docker\task_results\ci_pipeline_result.json"
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
