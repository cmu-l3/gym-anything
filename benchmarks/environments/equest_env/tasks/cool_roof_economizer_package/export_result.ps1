# Export script for cool_roof_economizer_package task.
# Reads the saved project .inp, extracts ABSORPTANCE and DRYBULB-LIMIT values,
# checks for .SIM file (proof simulation ran), and writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_cool_roof_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting cool_roof_economizer_package result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_cool_roof_economizer.txt"
    $resultPath  = "C:\Users\Docker\cool_roof_economizer_package_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Read baseline values recorded by setup
    $baselineEwallAbs = "unknown"
    $baselineRoofAbs  = "unknown"
    if (Test-Path "C:\Users\Docker\baseline_cool_roof_ewall_abs.txt") {
        try { $baselineEwallAbs = (Get-Content "C:\Users\Docker\baseline_cool_roof_ewall_abs.txt" -Raw).Trim() } catch { }
    }
    if (Test-Path "C:\Users\Docker\baseline_cool_roof_roof_abs.txt") {
        try { $baselineRoofAbs = (Get-Content "C:\Users\Docker\baseline_cool_roof_roof_abs.txt" -Raw).Trim() } catch { }
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

    # Parse saved project .inp for parameter values
    $ewallAbs              = [double]-1
    $roofAbs               = [double]-1
    $gDrybulbCorrectedCount = 0
    $gDrybulbValues        = @{}
    $gSystems              = @('G.S11','G.E12','G.N13','G.W14','G.C15')

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        # EWall Construction ABSORPTANCE
        $m = [regex]::Match($inpContent,
            '"EWall Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) {
            $ewallAbs = [double]$m.Groups[1].Value
            Write-Host "EWall ABSORPTANCE: $ewallAbs"
        }

        # Roof Construction ABSORPTANCE
        $m = [regex]::Match($inpContent,
            '"Roof Construction"\s*=\s*CONSTRUCTION[^.]*ABSORPTANCE\s*=\s*([\d.]+)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) {
            $roofAbs = [double]$m.Groups[1].Value
            Write-Host "Roof ABSORPTANCE: $roofAbs"
        }

        # G.* systems DRYBULB-LIMIT (5 Ground Floor systems)
        foreach ($sysCode in $gSystems) {
            $escapedName = [regex]::Escape('"Sys1 (PSZ) (' + $sysCode + ')"')
            $m = [regex]::Match($inpContent,
                $escapedName + '\s*=\s*SYSTEM[^.]*DRYBULB-LIMIT\s*=\s*([\d.]+)',
                [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $val = if ($m.Success) { [double]$m.Groups[1].Value } else { [double]-1 }
            $gDrybulbValues[$sysCode] = $val
            if ([Math]::Abs($val - 65.0) -le 0.5) { $gDrybulbCorrectedCount++ }
            Write-Host "G system $sysCode DRYBULB-LIMIT: $val"
        }
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    $result = [ordered]@{
        task                        = "cool_roof_economizer_package"
        task_start                  = $taskStart
        baseline_ewall_absorptance  = $baselineEwallAbs
        baseline_roof_absorptance   = $baselineRoofAbs
        ewall_absorptance           = $ewallAbs
        roof_absorptance            = $roofAbs
        g_drybulb_values            = $gDrybulbValues
        g_drybulb_corrected_count   = $gDrybulbCorrectedCount
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
