# PowerShell script content for export_result.ps1

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

# Define paths
$projectPath = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
$projectDir = Split-Path -Path $projectPath -Parent
$taskStartTimeFile = "C:\Users\Docker\task_start_time.txt"
$resultFile = "C:\Users\Docker\task_result.json"

# Load Start Time
$startTime = 0
if (Test-Path $taskStartTimeFile) {
    $startTime = [int64](Get-Content $taskStartTimeFile)
}

# --- Check 1: Simulation Run (.SIM file) ---
$simFileNew = $false
$simFiles = Get-ChildItem -Path $projectDir -Filter "*.SIM"
foreach ($file in $simFiles) {
    $mtime = [DateTimeOffset]::new($file.LastWriteTime).ToUnixTimeSeconds()
    if ($mtime -gt $startTime) {
        $simFileNew = $true
        break
    }
}

# --- Check 2: Parse .INP File for Material and Construction ---
$materialExists = $false
$matCond = -1.0
$matDens = -1.0
$matSH = -1.0
$roofHasLayer = $false
$layerThickness = -1.0

if (Test-Path $projectPath) {
    $content = Get-Content $projectPath -Raw
    
    # 1. Regex to find "Aerogel Blanket" definition
    # Pattern: "Aerogel Blanket" = MATERIAL ... TYPE = PROPERTIES ...
    # We look for the block. eQUEST INP format is roughly "Name" = TYPE ... ..
    
    # Simple parsing strategy: Split by ".." (end of object) and analyze blocks
    $blocks = $content -split "\.\."
    
    foreach ($block in $blocks) {
        if ($block -match '"Aerogel Blanket"\s*=\s*MATERIAL') {
            $materialExists = $true
            
            # Extract properties
            if ($block -match "CONDUCTIVITY\s*=\s*([0-9.]+)") { $matCond = $matches[1] }
            if ($block -match "DENSITY\s*=\s*([0-9.]+)") { $matDens = $matches[1] }
            if ($block -match "SPECIFIC-HEAT\s*=\s*([0-9.]+)") { $matSH = $matches[1] }
        }
        
        if ($block -match '"Roof Construction"\s*=\s*CONSTRUCTION') {
            # Check if Aerogel Blanket is in LAYERS
            if ($block -match '"Aerogel Blanket"') {
                $roofHasLayer = $true
                
                # Try to find thickness. 
                # Case A: Material has intrinsic thickness (not usual for PROPERTIES type unless specified)
                # Case B: CONSTRUCTION has THICKNESSES list.
                # Example: THICKNESSES = ( 0.01, 0.167, 0.05 )
                # We need to find the index of Aerogel Blanket in LAYERS and match with THICKNESSES
                
                # Extract LAYERS list
                if ($block -match 'LAYERS\s*=\s*\(([^)]+)\)') {
                    $layersStr = $matches[1]
                    $layers = $layersStr -split "," | ForEach-Object { $_.Trim().Trim('"') }
                    
                    # Find index
                    $index = -1
                    for ($i=0; $i -lt $layers.Count; $i++) {
                        if ($layers[$i] -eq "Aerogel Blanket") {
                            $index = $i
                            break
                        }
                    }
                    
                    if ($index -ge 0) {
                        # Extract THICKNESSES list
                        if ($block -match 'THICKNESSES\s*=\s*\(([^)]+)\)') {
                            $thicksStr = $matches[1]
                            $thicks = $thicksStr -split "," | ForEach-Object { $_.Trim() }
                            if ($index -lt $thicks.Count) {
                                $layerThickness = $thicks[$index]
                            }
                        }
                    }
                }
            }
        }
    }
}

# --- Construct JSON Result ---
$result = @{
    sim_file_new = $simFileNew
    material_exists = $materialExists
    material_conductivity = $matCond
    material_density = $matDens
    material_specific_heat = $matSH
    roof_uses_material = $roofHasLayer
    layer_thickness = $layerThickness
    timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

$json = $result | ConvertTo-Json
$json | Out-File -FilePath $resultFile -Encoding utf8 -Force

Write-Host "Result exported to $resultFile"
Get-Content $resultFile