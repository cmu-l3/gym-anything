# Same note as above: providing PowerShell content for export_result.ps1

<file name="export_result.ps1">
Write-Host "=== Exporting Task Results ==="

$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$ProjectFile = "$ProjectDir\4StoreyBuilding.inp"
$ResultFile = "C:\Users\Docker\task_result.json"
$StartTimeFile = "C:\Users\Docker\task_start_time.txt"

# 1. Check timestamps
$taskStart = 0
if (Test-Path $StartTimeFile) {
    $taskStart = [long](Get-Content $StartTimeFile)
}

$simFile = "$ProjectDir\4StoreyBuilding.SIM"
$simRan = $false
$simTimestamp = 0

if (Test-Path $simFile) {
    $item = Get-Item $simFile
    $simTimestamp = [DateTimeOffset]::new($item.LastWriteTime).ToUnixTimeSeconds()
    if ($simTimestamp -gt $taskStart) {
        $simRan = $true
    }
}

# 2. Parse INP file
$inpContent = ""
if (Test-Path $ProjectFile) {
    $inpContent = Get-Content $ProjectFile -Raw
}

# 2a. Verify Curve Creation
# Looking for: "HighEff_DX_PLR" = CURVE-FIT ... TYPE = QUADRATIC ... COEFFICIENTS = ( 0.085, 0.25, 0.665 )
$curveName = "HighEff_DX_PLR"
$curveExists = $false
$curveTypeCorrect = $false
$coeffsCorrect = $false

# Regex to find the curve block
# Matches "Name" = CURVE-FIT ... ..
if ($inpContent -match "(?s)`"$curveName`"\s*=\s*CURVE-FIT(.*?)\.\.") {
    $curveBlock = $matches[1]
    $curveExists = $true
    
    if ($curveBlock -match "TYPE\s*=\s*QUADRATIC") {
        $curveTypeCorrect = $true
    }
    
    # Check coefficients (allow flexible whitespace and trailing zeros)
    # Target: 0.085, 0.250, 0.665
    # Regex looks for: COEFFICIENTS = ( val1, val2, val3 )
    if ($curveBlock -match "COEFFICIENTS\s*=\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)") {
        $c1 = [double]$matches[1]
        $c2 = [double]$matches[2]
        $c3 = [double]$matches[3]
        
        # Tolerance check in Python verifier, just export values here
        $foundCoeffs = @($c1, $c2, $c3)
    }
}

# 2b. Verify System Assignments
# Systems: G.S1, G.E2, G.N3, G.W4, G.C5
# In INP they appear as "Sys1 (PSZ) (G.S1)" = SYSTEM
$targetSystems = @("G.S1", "G.E2", "G.N3", "G.W4", "G.C5")
$systemStatus = @{}

foreach ($sysTag in $targetSystems) {
    # Find the system block
    # Matches: "SysName" = SYSTEM ... ..
    # We look for definition containing the tag
    if ($inpContent -match "(?s)`"[^`"]*${sysTag}[^`"]*`"\s*=\s*SYSTEM(.*?)\.\.") {
        $sysBlock = $matches[1]
        # Check for COOL-EIR-FPLR = "HighEff_DX_PLR"
        if ($sysBlock -match "COOL-EIR-FPLR\s*=\s*`"$curveName`"") {
            $systemStatus[$sysTag] = $true
        } else {
            $systemStatus[$sysTag] = $false
        }
    } else {
        $systemStatus[$sysTag] = "Not Found"
    }
}

# 3. Take Final Screenshot
$finalScreenshot = "C:\Users\Docker\task_final.png"
Add-Type -AssemblyName System.Windows.Forms
$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($finalScreenshot)
$graphics.Dispose()
$bmp.Dispose()

# 4. Create JSON
$result = @{
    sim_ran = $simRan
    sim_timestamp = $simTimestamp
    task_start = $taskStart
    curve_data = @{
        exists = $curveExists
        type_correct = $curveTypeCorrect
        found_coeffs = $foundCoeffs
    }
    systems = $systemStatus
}

$result | ConvertTo-Json -Depth 5 | Out-File $ResultFile -Encoding utf8

Write-Host "Result exported to $ResultFile"
Get-Content $ResultFile
</file>