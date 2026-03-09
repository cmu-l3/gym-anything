# Note: This is a PowerShell script saved with .ps1 extension in the environment

Write-Host "=== Exporting Restroom Exhaust Fan Retrofit Result ==="

$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$ResultFile = "C:\Users\Docker\task_result.json"
$StartTimeFile = "C:\tmp\task_start_time.txt"

# 1. Get Task Start Time
if (Test-Path $StartTimeFile) {
    $TaskStart = Get-Content $StartTimeFile
} else {
    $TaskStart = 0
}

# 2. Check Simulation File (.SIM)
$SimFiles = Get-ChildItem -Path $ProjectDir -Filter "*.SIM" -Recurse
$SimRan = $false
$SimFile = $null

foreach ($file in $SimFiles) {
    $modTime = [int][double]::Parse((Get-Date -Date $file.LastWriteTime -UFormat %s))
    if ($modTime -gt $TaskStart) {
        $SimRan = $true
        $SimFile = $file.FullName
        break
    }
}

# 3. Parse INP File for Core Zones
# We look for ZONE definitions and specific parameters
# 4StoreyBuilding usually has zones like G.C05, M.C15, etc.
# We will verify any zone that has the target values.

$Content = Get-Content $InpFile -Raw

# Regex to find zones and their properties
# Structure: "ZoneName" = ZONE ... EXHAUST-FLOW = 300 ... ..
# This is complex to regex strictly, so we'll look for blocks.

# We will perform a line-by-line scan to handle the hierarchical nature simply
$lines = Get-Content $InpFile
$currentZone = ""
$zones = @{}

foreach ($line in $lines) {
    $line = $line.Trim()
    
    # Detect Zone Start: "Name" = ZONE
    if ($line -match '^"([^"]+)"\s*=\s*ZONE') {
        $currentZone = $matches[1]
        $zones[$currentZone] = @{
            "ExhaustFlow" = 0
            "ExhaustStatic" = 0
            "ExhaustEff" = 0
            "IsCore" = $false
        }
        
        # Heuristic for Core zone: contains "C" and not "Perim"
        if ($currentZone -match "C\d+" -or $currentZone -match "Core") {
             $zones[$currentZone]["IsCore"] = $true
        }
    }
    
    # Extract Parameters if inside a zone
    if ($currentZone -ne "") {
        if ($line -match "EXHAUST-FLOW\s*=\s*([0-9.]+)") {
            $zones[$currentZone]["ExhaustFlow"] = [double]$matches[1]
        }
        if ($line -match "EXHAUST-STATIC\s*=\s*([0-9.]+)") {
            $zones[$currentZone]["ExhaustStatic"] = [double]$matches[1]
        }
        if ($line -match "EXHAUST-EFF\s*=\s*([0-9.]+)") {
            $zones[$currentZone]["ExhaustEff"] = [double]$matches[1]
        }
        
        # End of object (simple heuristic, looking for "..")
        if ($line -eq "..") {
            $currentZone = ""
        }
    }
}

# Filter for Core zones that match requirements
$CorrectZones = @()
foreach ($key in $zones.Keys) {
    $z = $zones[$key]
    if ($z["IsCore"] -eq $true) {
        # Check values
        $flowMatch = [math]::Abs($z["ExhaustFlow"] - 300) -lt 5
        $staticMatch = [math]::Abs($z["ExhaustStatic"] - 0.5) -lt 0.05
        
        if ($flowMatch -and $staticMatch) {
            $CorrectZones += $key
        }
    }
}

# 4. Construct JSON Result
$ResultObject = @{
    "simulation_ran" = $SimRan
    "correct_zones_count" = $CorrectZones.Count
    "correct_zones_list" = $CorrectZones
    "timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$JsonOutput = $ResultObject | ConvertTo-Json -Depth 4
Set-Content -Path $ResultFile -Value $JsonOutput

Write-Host "Result exported to $ResultFile"
Write-Host $JsonOutput