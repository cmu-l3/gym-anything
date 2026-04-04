# Export script for top_floor_rtu_efficiency_upgrade task.
# Reads the saved project .inp, extracts COOLING-EIR / FURNACE-HIR / SUPPLY-EFF
# for all T.* PSZ systems, checks for .SIM file, and writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_top_floor_rtu_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting top_floor_rtu_efficiency_upgrade result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_top_floor_rtu.txt"
    $resultPath  = "C:\Users\Docker\top_floor_rtu_efficiency_upgrade_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Read baseline EIR recorded by setup
    $baselineEIR = "unknown"
    if (Test-Path "C:\Users\Docker\baseline_top_floor_cooling_eir.txt") {
        try { $baselineEIR = (Get-Content "C:\Users\Docker\baseline_top_floor_cooling_eir.txt" -Raw).Trim() } catch { }
    }

    # Check for .SIM file (confirms simulation ran)
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

    # Parse saved project .inp for T.* system parameters
    $tSystems = @('T.S31','T.E32','T.N33','T.W34','T.C35')
    $coolingEirValues  = @{}
    $furnaceHirValues  = @{}
    $supplyEffValues   = @{}
    $eirCorrectedCount = 0
    $hirCorrectedCount = 0
    $effCorrectedCount = 0

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        foreach ($sysCode in $tSystems) {
            $escapedName = [regex]::Escape('"Sys1 (PSZ) (' + $sysCode + ')"')
            $blockPattern = $escapedName + '\s*=\s*SYSTEM([^.]*)'

            $blockMatch = [regex]::Match($inpContent, $blockPattern,
                [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $block = if ($blockMatch.Success) { $blockMatch.Groups[1].Value } else { "" }

            # COOLING-EIR
            $m = [regex]::Match($block, 'COOLING-EIR\s*=\s*([\d.]+)')
            $eirVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $coolingEirValues[$sysCode] = $eirVal
            if ([Math]::Abs($eirVal - 0.28571) -le 0.005) { $eirCorrectedCount++ }

            # FURNACE-HIR
            $m = [regex]::Match($block, 'FURNACE-HIR\s*=\s*([\d.]+)')
            $hirVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $furnaceHirValues[$sysCode] = $hirVal
            if ([Math]::Abs($hirVal - 1.11111) -le 0.005) { $hirCorrectedCount++ }

            # SUPPLY-EFF
            $m = [regex]::Match($block, 'SUPPLY-EFF\s*=\s*([\d.]+)')
            $effVal = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $supplyEffValues[$sysCode] = $effVal
            if ([Math]::Abs($effVal - 0.65) -le 0.005) { $effCorrectedCount++ }

            Write-Host "T system $sysCode: EIR=$eirVal, HIR=$hirVal, SUPPLY-EFF=$effVal"
        }
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    $result = [ordered]@{
        task                        = "top_floor_rtu_efficiency_upgrade"
        task_start                  = $taskStart
        baseline_cooling_eir        = $baselineEIR
        cooling_eir_values          = $coolingEirValues
        furnace_hir_values          = $furnaceHirValues
        supply_eff_values           = $supplyEffValues
        cooling_eir_corrected_count = $eirCorrectedCount
        furnace_hir_corrected_count = $hirCorrectedCount
        supply_eff_corrected_count  = $effCorrectedCount
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
