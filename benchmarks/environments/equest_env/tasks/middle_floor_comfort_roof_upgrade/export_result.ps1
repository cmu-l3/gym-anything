# Export script for middle_floor_comfort_roof_upgrade task.
# Reads the saved 4StoreyBuilding project .inp, extracts DESIGN-COOL-T / DESIGN-HEAT-T
# for M.* zones and Roof ABSORPTANCE, checks .SIM, and writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_middle_floor_roof_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting middle_floor_comfort_roof_upgrade result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_middle_floor_roof.txt"
    $resultPath  = "C:\Users\Docker\middle_floor_comfort_roof_upgrade_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Read baselines recorded by setup
    $baselineRoofAbs   = "unknown"
    $baselineMidCoolT  = "unknown"
    if (Test-Path "C:\Users\Docker\baseline_mid_roof_abs.txt") {
        try { $baselineRoofAbs = (Get-Content "C:\Users\Docker\baseline_mid_roof_abs.txt" -Raw).Trim() } catch { }
    }
    if (Test-Path "C:\Users\Docker\baseline_mid_floor_cool_t.txt") {
        try { $baselineMidCoolT = (Get-Content "C:\Users\Docker\baseline_mid_floor_cool_t.txt" -Raw).Trim() } catch { }
    }

    # Check for .SIM file
    $simFileExists = $false
    $simFileMtime  = 0
    $simFileIsNew  = $false
    if (Test-Path $projDir) {
        $simFiles = Get-ChildItem -Path $projDir -Filter "*.sim" -Recurse -ErrorAction SilentlyContinue
        $simFileExists = ($null -ne $simFiles) -and ($simFiles.Count -gt 0)
        if ($simFileExists) {
            $latestSim    = $simFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            $simFileMtime = [int][DateTimeOffset]::new($latestSim.LastWriteTimeUtc).ToUnixTimeSeconds()
            $simFileIsNew = ($simFileMtime -gt $taskStart)
            Write-Host "Latest .SIM: $($latestSim.Name), mtime=$simFileMtime, is_new=$simFileIsNew"
        } else {
            Write-Host "No .SIM file found in $projDir"
        }
    }

    # M.* zone definitions (zone name → BDL name)
    $mZones = @(
        @{ key='M.S21'; name='South Perim Zn (M.S21)' },
        @{ key='M.E22'; name='East Perim Zn (M.E22)' },
        @{ key='M.N23'; name='North Perim Zn (M.N23)' },
        @{ key='M.W24'; name='West Perim Zn (M.W24)' },
        @{ key='M.C25'; name='Core Zn (M.C25)' }
    )

    $roofAbs             = [double]-1
    $coolTValues         = @{}
    $heatTValues         = @{}
    $coolTCorrectedCount = 0
    $heatTCorrectedCount = 0

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        # Roof Construction ABSORPTANCE (ECM 2)
        $m = [regex]::Match($inpContent,
            '"Roof Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) {
            $roofAbs = [double]$m.Groups[1].Value
            Write-Host "Roof ABSORPTANCE: $roofAbs"
        }

        # M.* zones: DESIGN-COOL-T and DESIGN-HEAT-T (ECM 1)
        foreach ($zone in $mZones) {
            $escapedName  = [regex]::Escape('"' + $zone.name + '"')
            $blockPattern = $escapedName + '\s*=\s*ZONE([^.]*)'
            $blockMatch   = [regex]::Match($inpContent, $blockPattern,
                [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $block = if ($blockMatch.Success) { $blockMatch.Groups[1].Value } else { "" }

            # DESIGN-COOL-T
            $m = [regex]::Match($block, 'DESIGN-COOL-T\s*=\s*([\d.]+)')
            $coolVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $coolTValues[$zone.key] = $coolVal
            if ([Math]::Abs($coolVal - 76.0) -le 0.5) { $coolTCorrectedCount++ }

            # DESIGN-HEAT-T
            $m = [regex]::Match($block, 'DESIGN-HEAT-T\s*=\s*([\d.]+)')
            $heatVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $heatTValues[$zone.key] = $heatVal
            if ([Math]::Abs($heatVal - 71.0) -le 0.5) { $heatTCorrectedCount++ }

            Write-Host "M zone $($zone.key): COOL-T=$coolVal, HEAT-T=$heatVal"
        }
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    $result = [ordered]@{
        task                        = "middle_floor_comfort_roof_upgrade"
        task_start                  = $taskStart
        baseline_roof_absorptance   = $baselineRoofAbs
        baseline_mid_cool_t         = $baselineMidCoolT
        roof_absorptance            = $roofAbs
        cool_t_values               = $coolTValues
        heat_t_values               = $heatTValues
        cool_t_corrected_count      = $coolTCorrectedCount
        heat_t_corrected_count      = $heatTCorrectedCount
        sim_file_exists             = $simFileExists
        sim_file_mtime              = $simFileMtime
        sim_file_is_new             = $simFileIsNew
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
