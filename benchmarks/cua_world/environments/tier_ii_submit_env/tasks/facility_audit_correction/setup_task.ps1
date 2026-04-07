[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up facility_audit_correction task ==="

. C:\workspace\scripts\task_utils.ps1

Stop-Tier2Submit

Remove-Item "C:\Users\Docker\Desktop\Tier2Output\facility_corrected.t2s" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Desktop\facility_audit_correction_result.json" -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Output" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Tasks" | Out-Null

# Create modified baseline with injected errors
$baselineSource = "C:\workspace\data\green_valley_baseline.t2s"
$modifiedBaseline = "C:\Users\Docker\Desktop\Tier2Tasks\facility_errors_baseline.t2s"
$extractDir = "C:\Users\Docker\Desktop\temp_modify_fac"

if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

try {
    # Extract the .t2s (ZIP with XML)
    $zipCopy = "$extractDir\baseline.zip"
    Copy-Item $baselineSource $zipCopy
    Expand-Archive -Path $zipCopy -DestinationPath $extractDir -Force
    Remove-Item $zipCopy -Force

    $xmlFile = Get-ChildItem $extractDir -Filter "*.xml" -Recurse | Select-Object -First 1
    if ($xmlFile) {
        $content = Get-Content $xmlFile.FullName -Raw -Encoding UTF8

        # Error 1: Wrong NAICS code (221310 → 221320)
        $content = $content -replace '<id>221310</id>', '<id>221320</id>'
        $content = $content -replace '<description>Water Supply and Irrigation Systems</description>', '<description>Sewage Treatment Facilities</description>'

        # Error 2: Wrong county (Chittenden → Addison)
        $content = $content -replace '<county>Chittenden</county>', '<county>Addison</county>'

        # Error 3: Wrong lat/long
        $content = $content -replace '<latitude>44.554437</latitude>', '<latitude>44.210000</latitude>'
        $content = $content -replace '<longitude>-73.167142</longitude>', '<longitude>-73.350000</longitude>'

        # Error 4: Wrong mailing city (Burlington → Montpelier)
        # Only change in mailingAddress, not streetAddress
        # The mailingAddress city appears after the mailing street
        $content = $content -replace '(<mailingAddress>[\s\S]*?<city>)Burlington(</city>)', '${1}Montpelier${2}'

        Set-Content -Path $xmlFile.FullName -Value $content -Encoding UTF8
        Write-Host "Injected 4 facility data errors into baseline."

        # Re-package as .t2s (ZIP)
        Compress-Archive -Path "$extractDir\*" -DestinationPath $modifiedBaseline -Force
        Write-Host "Modified baseline created: $modifiedBaseline"
    } else {
        Write-Host "ERROR: No XML file found in baseline .t2s"
        Copy-Item $baselineSource $modifiedBaseline -Force
    }
} catch {
    Write-Host "ERROR modifying baseline: $($_.Exception.Message)"
    Copy-Item $baselineSource $modifiedBaseline -Force
}

Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

# Also copy the clean chemical reference
Copy-Item "C:\workspace\data\chemical_reference.csv" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\chemical_reference.csv" -Force -ErrorAction SilentlyContinue

$startTime = Record-TaskStart -TaskName "facility_audit_correction"

# Launch Tier2 Submit
$t2sExe = Find-Tier2SubmitExe
Launch-Tier2SubmitInteractive -Tier2SubmitExe $t2sExe -WaitSeconds 20

$dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
if (Test-Path $dismissScript) {
    schtasks /Create /TN "DismissT2S_FacAudit" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "DismissT2S_FacAudit" 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN "DismissT2S_FacAudit" /F 2>$null
}

Write-Host "=== facility_audit_correction setup complete ==="
