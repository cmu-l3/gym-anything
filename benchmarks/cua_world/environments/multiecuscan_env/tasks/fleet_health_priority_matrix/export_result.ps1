Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting fleet_health_priority_matrix results ==="

$resultJson = "C:\Users\Docker\fleet_health_priority_matrix_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\fleet_priority_matrix.txt"
$tsFile     = "C:\Users\Docker\Desktop\MultiecuscanTasks\fleet_health_priority_matrix_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3

Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name                   = "fleet_health_priority_matrix"
    start_timestamp             = $startTimestamp
    report_exists               = $false
    report_file_size            = 0
    report_file_mtime           = 0
    report_content              = ""
    # Vehicle coverage
    has_vehicle_a_section       = $false   # Punto CNG
    has_vehicle_b_section       = $false   # Giulietta MultiAir
    has_vehicle_c_section       = $false   # Ducato diesel
    vehicles_covered_count      = 0
    # Report structure
    has_comparison_table        = $false
    has_priority_ranking        = $false
    has_preservice_actions      = $false
    has_downtime_estimate       = $false
    # Technical content
    all_dtcs_found              = @()
    vehicle_a_dtcs              = @()
    vehicle_b_dtcs              = @()
    vehicle_c_dtcs              = @()
    has_ecu_info_any            = $false
    has_parameters_any          = $false
    # Ranking
    priority_rank1_vehicle      = ""
    vehicles_id_present         = $false
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
        if ($raw -match "(?i)(FP14|NGP|Natural\s*Power|Punto.*CNG|CNG.*Punto|199B4)" -and
            $raw -match "(?i)(AR13|GLT|Giulietta|MultiAir|940A2)" -and
            $raw -match "(?i)(FD16|DUC|Ducato|F1AE0481|2\.3\s*Multijet)") {
            $result.vehicles_id_present = $true
        }

        # Vehicle A section (Punto CNG)
        if ($raw -match "(?i)(Vehicle\s*A|Punto|CNG|Natural\s*Power|FP14|199B4)") {
            $result.has_vehicle_a_section = $true
        }

        # Vehicle B section (Giulietta MultiAir)
        if ($raw -match "(?i)(Vehicle\s*B|Giulietta|MultiAir|940A2|AR13|GLT)") {
            $result.has_vehicle_b_section = $true
        }

        # Vehicle C section (Ducato diesel)
        if ($raw -match "(?i)(Vehicle\s*C|Ducato|F1AE0481|FD16|DUC|2\.3\s*Multijet|150HP|150\s*HP)") {
            $result.has_vehicle_c_section = $true
        }

        $sysCt = 0
        if ($result.has_vehicle_a_section) { $sysCt++ }
        if ($result.has_vehicle_b_section) { $sysCt++ }
        if ($result.has_vehicle_c_section) { $sysCt++ }
        $result.vehicles_covered_count = $sysCt

        # Extract DTC codes
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $allDtcs = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $allDtcs) { $allDtcs += $m.Value }
        }
        $result.all_dtcs_found = $allDtcs

        # ECU identification present
        if ($raw -match "(?i)(Part\s*Number|Hardware\s*Version|Software\s*Version|ECU\s*(Info|ID|Ident))") {
            $result.has_ecu_info_any = $true
        }

        # Parameter monitoring present
        if ($raw -match "(?i)(Coolant|RPM|Battery\s*Voltage|Intake|Fuel\s*(Pressure|Status)|Injection)") {
            $result.has_parameters_any = $true
        }

        # Comparison table
        if ($raw -match "(?i)(comparison\s*table|side.by.side|Vehicle\s*A.*Vehicle\s*B|compared|matrix\s*:)") {
            $result.has_comparison_table = $true
        }

        # Priority ranking
        if ($raw -match "(?i)(priority|rank|urgent|Rank\s*1|most\s*urgent|least\s*urgent)") {
            $result.has_priority_ranking = $true
        }

        # Which vehicle is rank 1 (most urgent)?
        if ($raw -match "(?i)(Rank\s*1|most\s*urgent|highest\s*priority)[^.]*?(Vehicle\s*A|Punto|CNG|FP14)") {
            $result.priority_rank1_vehicle = "Vehicle_A_Punto_CNG"
        } elseif ($raw -match "(?i)(Rank\s*1|most\s*urgent|highest\s*priority)[^.]*?(Vehicle\s*B|Giulietta|MultiAir|AR13)") {
            $result.priority_rank1_vehicle = "Vehicle_B_Giulietta"
        } elseif ($raw -match "(?i)(Rank\s*1|most\s*urgent|highest\s*priority)[^.]*?(Vehicle\s*C|Ducato|FD16|DUC)") {
            $result.priority_rank1_vehicle = "Vehicle_C_Ducato"
        }

        # Pre-service actions
        if ($raw -match "(?i)(pre.service|before\s*service|action|order|recommend|parts\s*to)") {
            $result.has_preservice_actions = $true
        }

        # Downtime / cost estimate
        if ($raw -match "(?i)(downtime|cost|labour|man.hour|days?\s*(off|out)|estimated\s*(time|cost|duration))") {
            $result.has_downtime_estimate = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Vehicles covered: $($result.vehicles_covered_count)/3"
Write-Host "Has comparison table: $($result.has_comparison_table)"
Write-Host "Has priority ranking: $($result.has_priority_ranking)"
Write-Host "Priority Rank 1: $($result.priority_rank1_vehicle)"
Write-Host "All DTCs: $($result.all_dtcs_found -join ', ')"
