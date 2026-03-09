#!/bin/bash
# Wrapper to call the PowerShell export script

cat > /workspace/tasks/dhw_loop_temperature_and_pump_retrofit/export_result.ps1 << 'PSEOF'
Write-Host "=== Exporting DHW Retrofit Results ==="

$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$ResultJson = "C:\Users\Docker\task_result.json"
$StartTimeFile = "C:\workspace\tasks\dhw_loop_temperature_and_pump_retrofit\task_start_time.txt"

# 1. Read Task Start Time
if (Test-Path $StartTimeFile) {
    $TaskStart = [int64](Get-Content $StartTimeFile)
} else {
    $TaskStart = 0
}

# 2. Check Simulation File (.SIM)
$SimFiles = Get-ChildItem -Path $ProjectDir -Filter "*.SIM"
$SimRan = $false
$SimFileTime = 0

foreach ($file in $SimFiles) {
    $WriteTime = [int64](($file.LastWriteTime) - (Get-Date "1/1/1970")).TotalSeconds
    if ($WriteTime -gt $TaskStart) {
        $SimRan = $true
        $SimFileTime = $WriteTime
        break
    }
}

# 3. Parse INP File for DHW Loop and Pump
# We look for CIRCULATION-LOOP with TYPE = DHW
# We look for PUMP with specific parameters

$Content = Get-Content $InpFile -Raw
# Remove comments (everything after ..)
# This is a simple parser; DOE-2 files can be complex, but for this task specific values are distinct.

# Regex to find DHW Loop Design T
# Looks for: "Loop Name" = CIRCULATION-LOOP ... TYPE = DHW ... LOOP-DESIGN-T = 120
# We will just scan for the text patterns in proximity or extract the values.

# Strategy: Split by command terminator ";"
$Commands = $Content -split ";"

$DhwLoopTemp = -1
$PumpHead = -1
$PumpEff = -1

foreach ($cmd in $Commands) {
    $cmd = $cmd.Trim()
    
    # Check for DHW Loop
    if ($cmd -match "CIRCULATION-LOOP") {
        if ($cmd -match "TYPE\s*=\s*DHW") {
            # Extract LOOP-DESIGN-T
            if ($cmd -match "LOOP-DESIGN-T\s*=\s*([\d\.]+)") {
                $DhwLoopTemp = $matches[1]
            }
        }
    }

    # Check for Pumps
    # We need to find the specific DHW pump. 
    # Usually attached to the loop found above, but parsing the hierarchy strictly is hard in regex.
    # However, standard practice in this specific file structure makes the DHW pump distinct.
    # We will look for ANY pump that has the target values, OR extract values from the likely candidate.
    
    if ($cmd -match "=\s*PUMP") {
        # Check if this pump has the modified values
        # If the agent modified the wrong pump, this might give a false positive if another pump matches.
        # But Head=20 is very specific (low), others are usually 60+.
        
        # Check Head
        if ($cmd -match "HEAD\s*=\s*([\d\.]+)") {
            $val = $matches[1]
            # If we find a pump with 20, we assume it's the one (since others are distinct)
            if ([double]$val -eq 20) {
                $PumpHead = $val
                
                # Check Eff in this same pump
                if ($cmd -match "MECH-EFF\s*=\s*([\d\.]+)") {
                    $PumpEff = $matches[1]
                }
            }
            # Also capture if it matches our expected "DHW Pump" name if we can guess it?
            # Let's fallback: If we haven't found a match yet, just record the last pump values found?
            # No, safer to initialize to -1 and overwrite if we find the specific target values
            # or keep list.
        }
    }
}

# Refined Logic:
# Since we can't easily parse the tree in bash/ps1 regex, we will extract ALL pumps and logic check later,
# OR we rely on the fact that if ANY pump has Head=20 AND Eff=0.75, they likely did it right 
# (as other pumps are for Chilled/Hot Water with much higher heads).

# Let's try to be specific: Find the block "DHW Pump" or similar if possible.
# In 4StoreyBuilding, it is usually "DHW Pump".
$DhwPumpHead = -1
$DhwPumpEff = -1

foreach ($cmd in $Commands) {
    if ($cmd -match '"DHW Pump"\s*=\s*PUMP') {
        if ($cmd -match "HEAD\s*=\s*([\d\.]+)") { $DhwPumpHead = $matches[1] }
        if ($cmd -match "MECH-EFF\s*=\s*([\d\.]+)") { $DhwPumpEff = $matches[1] }
    }
    # Fallback for generic naming if user renamed it (unlikely) or if name varies
    elseif ($cmd -match "CIRCULATION-LOOP" -and $cmd -match "TYPE\s*=\s*DHW") {
        # Extract Loop T
        if ($cmd -match "LOOP-DESIGN-T\s*=\s*([\d\.]+)") { $DhwLoopTemp = $matches[1] }
    }
}

# Construct JSON
$ResultObject = @{
    sim_ran = $SimRan
    dhw_loop_temp = $DhwLoopTemp
    pump_head = $DhwPumpHead
    pump_eff = $DhwPumpEff
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$ResultObject | ConvertTo-Json | Set-Content $ResultJson
Write-Host "Result saved to $ResultJson"
Type $ResultJson
PSEOF

# Execute the PowerShell script
powershell -ExecutionPolicy Bypass -File /workspace/tasks/dhw_loop_temperature_and_pump_retrofit/export_result.ps1