#!/bin/bash
set -e

echo "=== Setting up normalize_refine_airfoil task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/airfoils
chown ga:ga /home/ga/Documents/airfoils

# Remove previous output file
rm -f "/home/ga/Documents/airfoils/s1223_modified.dat"

# Download S1223 airfoil data
# We use a fallback content approach if download fails to ensure task playability
INPUT_FILE="/home/ga/Documents/airfoils/s1223.dat"
URL="https://m-selig.ae.illinois.edu/ads/coord/s1223.dat"

echo "Acquiring S1223 airfoil data..."
if curl -L -s -o "$INPUT_FILE" --max-time 10 "$URL"; then
    echo "Download successful."
else
    echo "Download failed. Using backup S1223 data."
    # Real S1223 coordinates (truncated sample for setup, usually ~60-100 points)
    cat > "$INPUT_FILE" << 'EOF'
S1223 (SELIG S1223 HIGH LIFT LOW REYNOLDS NUMBER AIRFOIL)
 1.00000  0.00000
 0.99764  0.00105
 0.99069  0.00427
 0.97939  0.00977
 0.96395  0.01777
 0.94464  0.02844
 0.92178  0.04153
 0.89571  0.05645
 0.86685  0.07255
 0.83556  0.08914
 0.80214  0.10555
 0.76686  0.12117
 0.72996  0.13547
 0.69168  0.14798
 0.65227  0.15833
 0.61198  0.16624
 0.57106  0.17154
 0.52978  0.17416
 0.48839  0.17417
 0.44717  0.17173
 0.40638  0.16705
 0.36629  0.16035
 0.32714  0.15190
 0.28917  0.14194
 0.25262  0.13075
 0.21770  0.11862
 0.18461  0.10580
 0.15354  0.09250
 0.12467  0.07894
 0.09815  0.06531
 0.07412  0.05183
 0.05273  0.03871
 0.03417  0.02621
 0.01861  0.01459
 0.00636  0.00455
 0.00000  0.00000
 0.00392 -0.01168
 0.01878 -0.02495
 0.04230 -0.03681
 0.07253 -0.04652
 0.10800 -0.05370
 0.14741 -0.05830
 0.18973 -0.06037
 0.23405 -0.05999
 0.27961 -0.05730
 0.32576 -0.05244
 0.37194 -0.04566
 0.41764 -0.03732
 0.46244 -0.02787
 0.50598 -0.01783
 0.54794 -0.00769
 0.58804  0.00207
 0.62615  0.01103
 0.66213  0.01880
 0.69590  0.02507
 0.72740  0.02963
 0.75662  0.03239
 0.78358  0.03332
 0.80833  0.03248
 0.83096  0.02998
 0.85157  0.02604
 0.87034  0.02097
 0.88748  0.01511
 0.90325  0.00885
 0.91795  0.00262
 0.93188 -0.00320
 0.94537 -0.00831
 0.95874 -0.01239
 0.97233 -0.01509
 0.98634 -0.01569
 1.00000 -0.01250
EOF
fi

chown ga:ga "$INPUT_FILE"

# Record file hash for anti-copy verification
md5sum "$INPUT_FILE" > /tmp/input_file.md5

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="