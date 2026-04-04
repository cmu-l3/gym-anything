# Export script for lshape_bb_floor_setpoint_rebalancing task.
# Reads the saved L_Shape project .inp, extracts DESIGN-COOL-T, DESIGN-HEAT-T,
# and SUPPLY-STATIC for all BB.* zones and systems, checks .SIM, writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_lshape_bb_setpoint_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting lshape_bb_floor_setpoint_rebalancing result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_lshape_bb_setpoint.txt"
    $resultPath  = "C:\Users\Docker\lshape_bb_floor_setpoint_rebalancing_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape\L_Shape.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Read baseline cool-T recorded by setup
    $baselineCoolT = "unknown"
    if (Test-Path "C:\Users\Docker\baseline_lshape_bb_cool_t.txt") {
        try { $baselineCoolT = (Get-Content "C:\Users\Docker\baseline_lshape_bb_cool_t.txt" -Raw).Trim() } catch { }
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

    # BB zone names and BB system names from L_Shape.inp
    $bbZones   = @(
        @{ key='BB.S1';  name='South Perim Zn (BB.S1)' },
        @{ key='BB.NE2'; name='NE Perim Zn (BB.NE2)' },
        @{ key='BB.NE3'; name='NE Perim Zn (BB.NE3)' },
        @{ key='BB.W4';  name='West Perim Zn (BB.W4)' },
        @{ key='BB.C5';  name='Core Zn (BB.C5)' }
    )
    $bbSystems = @('BB.C1','BB.C2','BB.C3','BB.C4','BB.C5')

    $coolTValues          = @{}
    $heatTValues          = @{}
    $supplyStaticValues   = @{}
    $coolTCorrectedCount  = 0
    $heatTCorrectedCount  = 0
    $staticCorrectedCount = 0

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        # BB zones: DESIGN-COOL-T and DESIGN-HEAT-T
        foreach ($zone in $bbZones) {
            $escapedName = [regex]::Escape('"' + $zone.name + '"')
            $blockPattern = $escapedName + '\s*=\s*ZONE([^.]*)'
            $blockMatch = [regex]::Match($inpContent, $blockPattern,
                [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $block = if ($blockMatch.Success) { $blockMatch.Groups[1].Value } else { "" }

            # DESIGN-COOL-T
            $m = [regex]::Match($block, 'DESIGN-COOL-T\s*=\s*([\d.]+)')
            $coolVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $coolTValues[$zone.key] = $coolVal
            if ([Math]::Abs($coolVal - 77.0) -le 0.5) { $coolTCorrectedCount++ }

            # DESIGN-HEAT-T
            $m = [regex]::Match($block, 'DESIGN-HEAT-T\s*=\s*([\d.]+)')
            $heatVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $heatTValues[$zone.key] = $heatVal
            if ([Math]::Abs($heatVal - 70.0) -le 0.5) { $heatTCorrectedCount++ }

            Write-Host "BB zone $($zone.key): COOL-T=$coolVal, HEAT-T=$heatVal"
        }

        # BB systems: SUPPLY-STATIC
        foreach ($sysCode in $bbSystems) {
            $escapedName = [regex]::Escape('"Sys1 (PSZ) (' + $sysCode + ')"')
            $blockPattern = $escapedName + '\s*=\s*SYSTEM([^.]*)'
            $blockMatch = [regex]::Match($inpContent, $blockPattern,
                [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $block = if ($blockMatch.Success) { $blockMatch.Groups[1].Value } else { "" }

            $m = [regex]::Match($block, 'SUPPLY-STATIC\s*=\s*([\d.]+)')
            $staticVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $supplyStaticValues[$sysCode] = $staticVal
            if ([Math]::Abs($staticVal - 1.1) -le 0.02) { $staticCorrectedCount++ }
            Write-Host "BB system $sysCode SUPPLY-STATIC: $staticVal"
        }
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    $result = [ordered]@{
        task                         = "lshape_bb_floor_setpoint_rebalancing"
        task_start                   = $taskStart
        baseline_cool_t              = $baselineCoolT
        cool_t_values                = $coolTValues
        heat_t_values                = $heatTValues
        supply_static_values         = $supplyStaticValues
        cool_t_corrected_count       = $coolTCorrectedCount
        heat_t_corrected_count       = $heatTCorrectedCount
        supply_static_corrected_count = $staticCorrectedCount
        sim_file_exists              = $simFileExists
        sim_file_mtime               = $simFileMtime
        sim_file_is_new              = $simFileIsNew
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
