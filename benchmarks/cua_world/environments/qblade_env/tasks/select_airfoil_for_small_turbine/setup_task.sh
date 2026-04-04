#!/bin/bash
set -e
echo "=== Setting up airfoil comparison task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory for task-specific airfoils
TASK_DATA_DIR="/home/ga/Documents/airfoils_task"
mkdir -p "$TASK_DATA_DIR"
mkdir -p "/home/ga/Documents/projects"
chown -R ga:ga "/home/ga/Documents"

# Create Clark-Y Airfoil File (Standard coordinates)
cat > "$TASK_DATA_DIR/clarky.dat" << 'EOF'
Clark Y Airfoil
   1.000000    0.000600
   0.990000    0.002800
   0.980000    0.005000
   0.970000    0.007100
   0.960000    0.009200
   0.950000    0.011300
   0.940000    0.013400
   0.930000    0.015400
   0.920000    0.017500
   0.910000    0.019600
   0.900000    0.021700
   0.800000    0.041300
   0.700000    0.057400
   0.600000    0.070200
   0.500000    0.079700
   0.400000    0.086300
   0.300000    0.088000
   0.200000    0.081800
   0.150000    0.074000
   0.100000    0.062000
   0.080000    0.055800
   0.060000    0.048500
   0.050000    0.044200
   0.040000    0.039400
   0.030000    0.034000
   0.020000    0.027600
   0.012000    0.021300
   0.005000    0.013200
   0.000000    0.000000
   0.005000   -0.007600
   0.012000   -0.011300
   0.020000   -0.013700
   0.030000   -0.015700
   0.040000   -0.017200
   0.050000   -0.018500
   0.060000   -0.019500
   0.080000   -0.021300
   0.100000   -0.022700
   0.150000   -0.025300
   0.200000   -0.027000
   0.300000   -0.028000
   0.400000   -0.027000
   0.500000   -0.024000
   0.600000   -0.019400
   0.700000   -0.014600
   0.800000   -0.009800
   0.900000   -0.004900
   0.910000   -0.004400
   0.920000   -0.003900
   0.930000   -0.003400
   0.940000   -0.002900
   0.950000   -0.002400
   0.960000   -0.002000
   0.970000   -0.001500
   0.980000   -0.001000
   0.990000   -0.000500
   1.000000    0.000000
EOF

# Create NACA 4412 Airfoil File
cat > "$TASK_DATA_DIR/naca4412.dat" << 'EOF'
NACA 4412
   1.000000    0.001300
   0.950000    0.011400
   0.900000    0.020800
   0.800000    0.037500
   0.700000    0.051800
   0.600000    0.063600
   0.500000    0.072900
   0.400000    0.079600
   0.300000    0.083000
   0.250000    0.083300
   0.200000    0.082200
   0.150000    0.078900
   0.100000    0.072600
   0.075000    0.067900
   0.050000    0.061700
   0.025000    0.052000
   0.012500    0.043600
   0.000000    0.000000
   0.012500   -0.014300
   0.025000   -0.019500
   0.050000   -0.026500
   0.075000   -0.031200
   0.100000   -0.035000
   0.150000   -0.040700
   0.200000   -0.044600
   0.250000   -0.047400
   0.300000   -0.049200
   0.400000   -0.050600
   0.500000   -0.049300
   0.600000   -0.045600
   0.700000   -0.039800
   0.800000   -0.031900
   0.900000   -0.020800
   0.950000   -0.013200
   1.000000   -0.001300
EOF

chown ga:ga "$TASK_DATA_DIR"/*.dat

# Clean up any previous results
rm -f /home/ga/Documents/projects/airfoil_comparison.wpa
rm -f /home/ga/Documents/projects/airfoil_selection_report.txt

# Start QBlade
echo "Starting QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 60

# Maximize for visibility
wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="