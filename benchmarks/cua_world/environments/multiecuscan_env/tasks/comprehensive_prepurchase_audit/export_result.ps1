Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting comprehensive_prepurchase_audit results ==="

$resultJson = "C:\Users\Docker\comprehensive_prepurchase_audit_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\prepurchase_certificate.txt"
$tsFile     = "C:\Users\Docker\Desktop\MultiecuscanTasks\comprehensive_prepurchase_audit_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3

Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name               = "comprehensive_prepurchase_audit"
    start_timestamp         = $startTimestamp
    report_exists           = $false
    report_file_size        = 0
    report_file_mtime       = 0
    report_content          = ""
    has_engine_section      = $false
    has_transmission_section = $false
    has_abs_section         = $false
    has_body_computer_section = $false
    has_airbag_section      = $false
    systems_covered_count   = 0
    has_dtc_classification  = $false
    has_risk_score          = $false
    has_verdict             = $false
    verdict_value           = ""
    risk_score_value        = -1
    has_critical_mention    = $false
    has_major_mention       = $false
    all_dtcs_found          = @()
    vehicle_id_present      = $false
    has_cover_page          = $false
}

if (Test-Path $reportFile) {
    $fileInfo = Get-Item $reportFile
    $result.report_exists    = $true
    $result.report_file_size = $fileInfo.Length
    $result.report_file_mtime = [int][double]::Parse(
        (Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))

    $raw = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        if ($raw.Length -gt 80000) { $raw = $raw.Substring(0, 80000) }
        $result.report_content = $raw

        # Vehicle identification
        if ($raw -match "(?i)(Ducato|YN16|ZFA250|2\.3\s*Multijet|F1AE|187[,\.]?4)") {
            $result.vehicle_id_present = $true
        }

        # Cover page
        if ($raw -match "(?i)(pre.purchase|inspection\s*certificate|inspection\s*report|cover\s*page|vehicle\s*details)") {
            $result.has_cover_page = $true
        }

        # Individual system sections
        $sysCt = 0
        if ($raw -match "(?i)(Engine\s*ECU|Engine\s*Control|F1AE|2\.3\s*Multijet|diesel\s*engine)") {
            $result.has_engine_section = $true; $sysCt++
        }
        if ($raw -match "(?i)(Transmission|Gearbox|transfer\s*case|gear\s*ECU|ZF\s*gearbox)") {
            $result.has_transmission_section = $true; $sysCt++
        }
        if ($raw -match "(?i)(ABS|Anti.lock|Braking\s*(System|ECU)|wheel\s*speed|ESP)") {
            $result.has_abs_section = $true; $sysCt++
        }
        if ($raw -match "(?i)(Body\s*Computer|BSI|BCM|Body\s*System)") {
            $result.has_body_computer_section = $true; $sysCt++
        }
        if ($raw -match "(?i)(Airbag|SRS|Supplemental\s*Restraint|curtain\s*bag|deployed)") {
            $result.has_airbag_section = $true; $sysCt++
        }
        $result.systems_covered_count = $sysCt

        # DTC classification
        if ($raw -match "(?i)(CRITICAL|MAJOR|MINOR|CLEARED|safety\s*defect|must\s*repair)") {
            $result.has_dtc_classification = $true
        }
        if ($raw -match "(?i)CRITICAL") { $result.has_critical_mention = $true }
        if ($raw -match "(?i)MAJOR") { $result.has_major_mention = $true }

        # Extract DTC codes
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $allDtcs = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $allDtcs) { $allDtcs += $m.Value }
        }
        $result.all_dtcs_found = $allDtcs

        # Risk score
        if ($raw -match "(?i)(risk\s*score|overall\s*score|risk\s*rating|score\s*:\s*\d+)") {
            $result.has_risk_score = $true
            $scoreMatch = [regex]::Match($raw, "(?i)(?:risk\s*score|overall\s*score|score)\s*[:\-]?\s*(\d+)")
            if ($scoreMatch.Success) {
                $result.risk_score_value = [int]$scoreMatch.Groups[1].Value
            }
        }

        # Verdict
        if ($raw -match "(?i)(RECOMMENDED|NOT\s*RECOMMENDED|CONDITIONAL|verdict|conclusion|do\s*not\s*buy|proceed)") {
            $result.has_verdict = $true
            if ($raw -match "(?i)\bNOT\s*RECOMMENDED\b") { $result.verdict_value = "NOT_RECOMMENDED" }
            elseif ($raw -match "(?i)\bCONDITIONAL(LY)?\s*RECOMMENDED\b") { $result.verdict_value = "CONDITIONAL" }
            elseif ($raw -match "(?i)\bRECOMMENDED\b") { $result.verdict_value = "RECOMMENDED" }
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Systems covered: $($result.systems_covered_count)/5"
Write-Host "Has risk score: $($result.has_risk_score) (value: $($result.risk_score_value))"
Write-Host "Verdict: $($result.verdict_value)"
Write-Host "DTCs found: $($result.all_dtcs_found.Count)"
