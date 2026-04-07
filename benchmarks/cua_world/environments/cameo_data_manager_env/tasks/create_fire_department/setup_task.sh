# Note: This is a PowerShell script saved with .ps1 extension in the environment
# We use .sh extension here for syntax highlighting in the prompt block, 
# but the content is PowerShell.

$ErrorActionPreference = "Stop"
Write-Output "=== Setting up Create Fire Department Task ==="

# 1. Setup paths and timestamps
$docPath = "C:\Users\Docker\Documents"
if (-not (Test-Path $docPath)) { New-Item -ItemType Directory -Path $docPath | Out-Null }

# Record start time
$startTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Set-Content -Path "C:\workspace\task_start_time.txt" -Value $startTime

# 2. Clean previous run artifacts
Remove-Item "$docPath\fd_verification.txt" -ErrorAction SilentlyContinue
Remove-Item "$docPath\fd_association_proof.png" -ErrorAction SilentlyContinue

# 3. Create dummy facility import file (Simulating pre-loaded data)
# Since we can't easily inject into CAMEO's binary DB, we create a valid Tier2 Submit file
# that the agent *could* import, but we'll try to automate the import or just assume
# the agent handles the facility creation if it's missing. 
# BETTER: We will create a "Starting Database" state by copying a pre-prepared folder if available.
# FALLBACK: We create a text file with facility details so the agent can create it if missing.
$facilityInfo = @"
FACILITY DATA FOR TASK
Name: Midwest Agricultural Chemicals LLC
Address: 2400 South Main Street, Chatham, IL 62629
"@
Set-Content -Path "$docPath\facility_info.txt" -Value $facilityInfo

# 4. Start CAMEO Data Manager
Write-Output "Starting CAMEO Data Manager..."
$cameoPath = "C:\Program Files (x86)\CAMEO Data Manager\CAMEO Data Manager.exe"

# Check if running
$process = Get-Process "CAMEO Data Manager" -ErrorAction SilentlyContinue
if (-not $process) {
    if (Test-Path $cameoPath) {
        Start-Process $cameoPath
        Start-Sleep -Seconds 10
    } else {
        Write-Output "WARNING: CAMEO executable not found at standard path."
    }
}

# 5. Capture Initial State Screenshot
# Using a PowerShell snippet to capture screen
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
$bitmap.Save("C:\workspace\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Output "=== Setup Complete ==="