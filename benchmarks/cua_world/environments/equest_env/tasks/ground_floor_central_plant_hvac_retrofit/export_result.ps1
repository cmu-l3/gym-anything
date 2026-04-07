# Export script for ground_floor_central_plant_hvac_retrofit task.
# Reads the saved project .inp, extracts plant and system parameters,
# checks for .SIM file (proof simulation ran), and writes result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_central_plant_retrofit_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting ground_floor_central_plant_hvac_retrofit result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_central_plant_retrofit.txt"
    $resultPath  = "C:\Users\Docker\central_plant_retrofit_result.json"
    $projInp     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
    $projDir     = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # --- Check for .SIM file (confirms simulation ran) ---
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

    # --- Initialize result containers ---
    $loops    = @{}
    $chillers = @{}
    $boilers  = @{}
    $systems  = @{}
    $gSystemCodes = @('G.S11','G.E12','G.N13','G.W14','G.C15')

    if (Test-Path $projInp) {
        $inpContent = Get-Content $projInp -Raw
        Write-Host "Read project .inp ($($inpContent.Length) chars)"

        # === Parse CIRCULATION-LOOP objects ===
        $loopMatches = [regex]::Matches($inpContent,
            '"([^"]+)"\s*=\s*CIRCULATION-LOOP([\s\S]*?)\.\.')
        foreach ($m in $loopMatches) {
            $loopName  = $m.Groups[1].Value
            $loopBlock = $m.Groups[2].Value
            $loopInfo  = @{ name = $loopName }

            $tm = [regex]::Match($loopBlock, 'TYPE\s*=\s*(\S+)')
            if ($tm.Success) { $loopInfo['type'] = $tm.Groups[1].Value }

            $tm = [regex]::Match($loopBlock, 'COOL-SETPT-T\s*=\s*([\d.]+)')
            if ($tm.Success) { $loopInfo['cool_setpt_t'] = [double]$tm.Groups[1].Value }

            $tm = [regex]::Match($loopBlock, 'HEAT-SETPT-T\s*=\s*([\d.]+)')
            if ($tm.Success) { $loopInfo['heat_setpt_t'] = [double]$tm.Groups[1].Value }

            $tm = [regex]::Match($loopBlock, 'LOOP-DESIGN-DT\s*=\s*([\d.]+)')
            if ($tm.Success) { $loopInfo['loop_design_dt'] = [double]$tm.Groups[1].Value }

            $loops[$loopName] = $loopInfo
            Write-Host "Found CIRCULATION-LOOP: $loopName (type=$($loopInfo['type']))"
        }

        # === Parse CHILLER objects ===
        $chillerMatches = [regex]::Matches($inpContent,
            '"([^"]+)"\s*=\s*CHILLER([\s\S]*?)\.\.')
        foreach ($m in $chillerMatches) {
            $name  = $m.Groups[1].Value
            $block = $m.Groups[2].Value
            $info  = @{ name = $name }

            $tm = [regex]::Match($block, 'TYPE\s*=\s*(\S+)')
            if ($tm.Success) { $info['type'] = $tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'CHW-LOOP\s*=\s*"([^"]+)"')
            if ($tm.Success) { $info['chw_loop'] = $tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'ELEC-INPUT-RATIO\s*=\s*([\d.]+)')
            if ($tm.Success) { $info['eir'] = [double]$tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'CAPACITY\s*=\s*([\d.]+)')
            if ($tm.Success) { $info['capacity'] = [double]$tm.Groups[1].Value }

            $chillers[$name] = $info
            Write-Host "Found CHILLER: $name (type=$($info['type']))"
        }

        # === Parse BOILER objects ===
        $boilerMatches = [regex]::Matches($inpContent,
            '"([^"]+)"\s*=\s*BOILER([\s\S]*?)\.\.')
        foreach ($m in $boilerMatches) {
            $name  = $m.Groups[1].Value
            $block = $m.Groups[2].Value
            $info  = @{ name = $name }

            $tm = [regex]::Match($block, 'TYPE\s*=\s*(\S+)')
            if ($tm.Success) { $info['type'] = $tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'HW-LOOP\s*=\s*"([^"]+)"')
            if ($tm.Success) { $info['hw_loop'] = $tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'HEAT-INPUT-RATIO\s*=\s*([\d.]+)')
            if ($tm.Success) { $info['hir'] = [double]$tm.Groups[1].Value }

            $tm = [regex]::Match($block, 'CAPACITY\s*=\s*([\d.]+)')
            if ($tm.Success) { $info['capacity'] = [double]$tm.Groups[1].Value }

            $boilers[$name] = $info
            Write-Host "Found BOILER: $name (type=$($info['type']))"
        }

        # === Parse Ground Floor SYSTEM objects ===
        foreach ($sysCode in $gSystemCodes) {
            $escapedName = [regex]::Escape('"Sys1 (PSZ) (' + $sysCode + ')"')
            $blockPattern = $escapedName + '\s*=\s*SYSTEM([\s\S]*?)\.\.'
            $sm = [regex]::Match($inpContent, $blockPattern)

            $sysInfo = @{ code = $sysCode }
            if ($sm.Success) {
                $block = $sm.Groups[1].Value

                $tm = [regex]::Match($block, 'COOL-SOURCE\s*=\s*(\S+)')
                if ($tm.Success) { $sysInfo['cool_source'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'CHW-LOOP\s*=\s*"([^"]+)"')
                if ($tm.Success) { $sysInfo['chw_loop'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'HEAT-SOURCE\s*=\s*(\S+)')
                if ($tm.Success) { $sysInfo['heat_source'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'HW-LOOP\s*=\s*"([^"]+)"')
                if ($tm.Success) { $sysInfo['hw_loop'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'RECOVER-EXHAUST\s*=\s*(\S+)')
                if ($tm.Success) { $sysInfo['recover_exhaust'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'ERV-RECOVER-TYPE\s*=\s*(\S+)')
                if ($tm.Success) { $sysInfo['erv_recover_type'] = $tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'ERV-SENSIBLE-EFF\s*=\s*([\d.]+)')
                if ($tm.Success) { $sysInfo['erv_sensible_eff'] = [double]$tm.Groups[1].Value }

                $tm = [regex]::Match($block, 'ERV-LATENT-EFF\s*=\s*([\d.]+)')
                if ($tm.Success) { $sysInfo['erv_latent_eff'] = [double]$tm.Groups[1].Value }

                Write-Host "System $sysCode : COOL-SOURCE=$($sysInfo['cool_source']), HEAT-SOURCE=$($sysInfo['heat_source'])"
            } else {
                Write-Host "WARNING: System Sys1 (PSZ) ($sysCode) not found in .inp"
            }

            $systems[$sysCode] = $sysInfo
        }
    } else {
        Write-Host "WARNING: Project .inp not found at $projInp"
    }

    # --- Assemble and write result JSON ---
    $result = [ordered]@{
        task            = "ground_floor_central_plant_hvac_retrofit"
        task_start      = $taskStart
        sim_file_exists = $simFileExists
        sim_file_mtime  = $simFileMtime
        sim_file_is_new = $simFileIsNew
        loops           = $loops
        chillers        = $chillers
        boilers         = $boilers
        systems         = $systems
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
