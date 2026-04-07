#!/bin/bash
echo "=== Setting up calculate_polygon_area task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the survey data file
DATA_DIR="/c/Users/Docker/Documents"
mkdir -p "$DATA_DIR"
CSV_FILE="$DATA_DIR/foothills_parcel_survey.csv"

# Remove any previous artifacts
rm -f "$DATA_DIR/parcel_area_report.txt" 2>/dev/null || true

# Generate realistic coordinate dataset (UTM Zone 13N, Colorado)
cat > "$CSV_FILE" << 'EOF'
1,476520.45,4399815.20,1842.35,BM
2,476658.30,4399822.75,1856.80,BM
3,476672.15,4399935.40,1871.25,BM
4,476589.60,4399978.85,1863.90,BM
5,476502.80,4399912.50,1849.15,BM
6,476550.00,4399860.00,1852.10,TOPO
7,476580.25,4399842.30,1848.65,TOPO
8,476610.50,4399870.90,1857.30,TOPO
9,476545.80,4399905.60,1855.40,TOPO
10,476620.35,4399920.15,1865.70,TOPO
11,476570.90,4399880.45,1854.20,TOPO
12,476535.15,4399840.80,1846.90,ROAD
13,476560.40,4399835.25,1849.75,ROAD
14,476595.70,4399830.60,1851.30,ROAD
15,476630.85,4399838.10,1854.45,ROAD
16,476655.20,4399855.70,1859.60,TOPO
17,476660.90,4399890.35,1866.15,TOPO
18,476645.30,4399945.80,1869.80,TOPO
19,476615.75,4399960.25,1867.40,TOPO
20,476565.40,4399950.70,1860.55,TOPO
21,476525.60,4399935.15,1853.80,TREE
22,476510.85,4399875.40,1847.60,TREE
23,476540.20,4399895.30,1853.95,TREE
24,476600.60,4399900.50,1861.25,TOPO
25,476575.35,4399855.90,1850.80,TOPO
26,476640.10,4399875.45,1862.35,TOPO
27,476555.70,4399925.80,1857.90,TOPO
28,476608.45,4399940.30,1864.50,TOPO
EOF

# Ensure TopoCal is running using PowerShell
powershell.exe -ExecutionPolicy Bypass -Command "
    \$proc = Get-Process -Name 'TopoCal*' -ErrorAction SilentlyContinue
    if (-not \$proc) {
        Write-Host 'Starting TopoCal...'
        Start-Process 'C:\Program Files\TopoCal\TopoCal.exe' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 8
    }
"

# Give TopoCal a moment to settle
sleep 3

# Take initial screenshot of the starting state using PowerShell
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$bitmap = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen([System.Drawing.Point]::Empty, [System.Drawing.Point]::Empty, \$bitmap.Size)
    \$bitmap.Save('C:\tmp\task_initial.png')
    \$graphics.Dispose()
    \$bitmap.Dispose()
" 2>/dev/null || true

echo "=== Task setup complete ==="