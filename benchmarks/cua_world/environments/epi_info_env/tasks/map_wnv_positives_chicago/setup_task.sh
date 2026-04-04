#!/bin/bash
echo "=== Setting up Map WNV Positives Task ==="

# Define paths (Git Bash / Cygwin style for Windows)
DATA_DIR="/c/Users/Docker/Documents/EpiData"
CSV_FILE="$DATA_DIR/Chicago_WNV_Tests.csv"
START_MARKER="/tmp/task_start_time.txt"

# Create directory
mkdir -p "$DATA_DIR"

# Clean up previous artifacts
rm -f "$DATA_DIR/wnv_positive_map.png"
rm -f "$START_MARKER"

# Record start time for anti-gaming verification
date +%s > "$START_MARKER"

# Generate Realistic Data (Chicago WNV Style)
# We generate this to ensure reliability and avoid external dependency failures
echo "Generating dataset at $CSV_FILE..."

cat > "$CSV_FILE" << EOF
TEST_ID,DATE,RESULT,LATITUDE,LONGITUDE,SPECIES,BLOCK
1001,2019-08-01,negative,41.9546,-87.8009,CULEX PIPIENS,100XX W OHARE
1002,2019-08-01,negative,41.7434,-87.7314,CULEX RESTUANS,82XX S KOSTNER
1003,2019-08-02,positive,41.9741,-87.8906,CULEX PIPIENS,10XX E 67TH
1004,2019-08-02,negative,41.9216,-87.6664,CULEX RESTUANS,22XX N CANNON
1005,2019-08-03,positive,41.8007,-87.5293,CULEX PIPIENS,52XX S KOLMAR
1006,2019-08-03,positive,41.6446,-87.5401,CULEX PIPIENS,13XX E 133RD
1007,2019-08-04,negative,41.8681,-87.6963,CULEX RESTUANS,24XX W 24TH
1008,2019-08-04,positive,41.9739,-87.7711,CULEX PIPIENS,50XX N UNION
1009,2019-08-05,negative,41.7637,-87.7423,CULEX RESTUANS,36XX W 63RD
1010,2019-08-05,positive,41.9042,-87.7491,CULEX PIPIENS,5XX N LARAMIE
1011,2019-08-06,negative,41.9642,-87.7565,CULEX RESTUANS,45XX N CAMPBELL
1012,2019-08-06,positive,41.7764,-87.6273,CULEX PIPIENS,65XX S STATE
1013,2019-08-07,negative,41.8333,-87.6255,CULEX RESTUANS,30XX S MICHIGAN
1014,2019-08-07,positive,41.9991,-87.7955,CULEX PIPIENS,70XX N MOZART
1015,2019-08-08,negative,41.6734,-87.6687,CULEX RESTUANS,119XX S PEORIA
EOF

# Ensure file permissions
chmod 666 "$CSV_FILE"

# Close any running instances of Epi Info to ensure clean start
if command -v taskkill >/dev/null 2>&1; then
    taskkill //IM "EpiInfo.exe" //F >/dev/null 2>&1 || true
    taskkill //IM "EpiMap.exe" //F >/dev/null 2>&1 || true
fi

# Attempt to launch Epi Info Menu (optional helper)
# We leave it to the agent to navigate, but ensuring the app is ready is good.
# Using powershell to start the process in the background
echo "Ensuring Epi Info is ready..."
powershell -Command "Start-Process 'C:\Epi Info 7\EpiInfo.exe' -WindowStyle Maximized" >/dev/null 2>&1 || echo "Could not auto-launch, agent must launch manually."

# Capture initial screenshot (using PowerShell fallback for Windows)
echo "Capturing initial state..."
powershell -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.Location, [System.Drawing.Point]::Empty, \$screen.Bounds.Size)
\$bitmap.Save('C:\\Users\\Docker\\AppData\\Local\\Temp\\task_initial.png', [System.Drawing.Imaging.ImageFormat]::Png)
\$graphics.Dispose()
\$bitmap.Dispose()
" >/dev/null 2>&1 || true

# Copy screenshot to expected Linux path if mapped, or keep in temp
cp "/c/Users/Docker/AppData/Local/Temp/task_initial.png" /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="