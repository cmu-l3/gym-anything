# Export script for lshape_lighting_power_density_reduction task.
# Reads the saved L_Shape project .inp, counts LIGHTING-W/AREA and EQUIPMENT-W/AREA
# occurrences at target vs. baseline values, checks .SIM, and writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_lshape_lpd_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting lshape_lighting_power_density_reduction result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_lshape_lpd.txt"
    $resultPath  = "C:\Users\Docker\lshape_lighting_power_density_reduction_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape\L_Shape.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\L_Shape"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Read baseline LPD count recorded by setup
    $baselineLpdCount = 0
    if (Test-Path "C:\Users\Docker\baseline_lshape_lpd_count.txt") {
        try { $baselineLpdCount = [int](Get-Content "C:\Users\Docker\baseline_lshape_lpd_count.txt" -Raw).Trim() } catch { }
    }
    Write-Host "Baseline LIGHTING-W/AREA=1.3 count: $baselineLpdCount"

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

    # Count lighting and equipment load occurrences in saved .inp
    $lpd13RemainingCount  = 0   # spaces still at 1.3 (should be 0 after task)
    $lpd105Count          = 0   # spaces now at 1.05 (target)
    $equip15RemainingCount = 0  # spaces still at 1.5 (should be 0 after task)
    $equip12Count         = 0   # spaces now at 1.2 (target)

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        # Count remaining original-value spaces (anti-gaming: should be 0 when done)
        $lpd13Matches  = [regex]::Matches($inpContent, 'LIGHTING-W/AREA\s*=\s*1\.3\b')
        $lpd13RemainingCount = $lpd13Matches.Count
        Write-Host "LIGHTING-W/AREA=1.3 remaining: $lpd13RemainingCount"

        # Count newly set target-value spaces
        $lpd105Matches = [regex]::Matches($inpContent, 'LIGHTING-W/AREA\s*=\s*1\.05\b')
        $lpd105Count   = $lpd105Matches.Count
        Write-Host "LIGHTING-W/AREA=1.05 new: $lpd105Count"

        # Equipment: remaining original value
        $equip15Matches = [regex]::Matches($inpContent, 'EQUIPMENT-W/AREA\s*=\s*1\.5\b')
        $equip15RemainingCount = $equip15Matches.Count
        Write-Host "EQUIPMENT-W/AREA=1.5 remaining: $equip15RemainingCount"

        # Equipment: newly set target value
        $equip12Matches = [regex]::Matches($inpContent, 'EQUIPMENT-W/AREA\s*=\s*1\.2\b')
        $equip12Count   = $equip12Matches.Count
        Write-Host "EQUIPMENT-W/AREA=1.2 new: $equip12Count"
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    $result = [ordered]@{
        task                        = "lshape_lighting_power_density_reduction"
        task_start                  = $taskStart
        baseline_lpd13_count        = $baselineLpdCount
        lpd13_remaining_count       = $lpd13RemainingCount
        lpd105_count                = $lpd105Count
        equip15_remaining_count     = $equip15RemainingCount
        equip12_count               = $equip12Count
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
