# This is actually a PowerShell script (export_result.ps1)
# labeled as .sh in the block for consistency with the prompt requirements 
# but the content is PowerShell.

<#
.SYNOPSIS
Export script for configure_linux_server_audit task
#>

Write-Host "=== Exporting Task Results ==="

$resultFile = "C:\workspace\task_result.json"
$screenshotPath = "C:\workspace\linux_audit_evidence.png"

# 1. Capture basic state
$taskEndTime = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
$taskStartTime = 0
if (Test-Path "C:\workspace\task_start_time.txt") {
    $taskStartTime = Get-Content "C:\workspace\task_start_time.txt"
}

# 2. Verify screenshot exists
$screenshotExists = $false
$screenshotSize = 0
if (Test-Path $screenshotPath) {
    $screenshotExists = $true
    $screenshotSize = (Get-Item $screenshotPath).Length
}

# 3. Attempt to find 'bastion01' in config files
# ADAudit Plus often keeps config in XML or flat files in /conf
$installDir = "C:\Program Files\ManageEngine\ADAudit Plus"
$foundInConfig = $false
$configFile = ""

# Search pattern in conf directory (recursive)
if (Test-Path $installDir) {
    try {
        $matches = Get-ChildItem -Path "$installDir\conf" -Recurse -Filter "*.xml" -ErrorAction SilentlyContinue | 
                   Select-String -Pattern "bastion01" -SimpleMatch
        if ($matches) {
            $foundInConfig = $true
            $configFile = $matches[0].Path
            Write-Host "Found 'bastion01' in config: $configFile"
        }
    } catch {
        Write-Host "Error searching config files: $_"
    }
}

# 4. Create JSON Result
$result = @{
    task_start = $taskStartTime
    task_end = $taskEndTime
    screenshot_exists = $screenshotExists
    screenshot_path = $screenshotPath
    screenshot_size_bytes = $screenshotSize
    found_in_config_file = $foundInConfig
    config_file_path = $configFile
    target_host = "bastion01"
}

$jsonContent = $result | ConvertTo-Json -Depth 2
Set-Content -Path $resultFile -Value $jsonContent

Write-Host "Result exported to $resultFile"
Get-Content $resultFile