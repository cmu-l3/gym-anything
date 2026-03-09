#!/bin/bash
set -e
echo "=== Setting up Clean and Import Airfoil Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directories
INCOMING_DIR="/home/ga/Documents/incoming"
PROJECTS_DIR="/home/ga/Documents/projects"
mkdir -p "$INCOMING_DIR"
mkdir -p "$PROJECTS_DIR"

# Clean up previous artifacts
rm -f "$INCOMING_DIR/project_falcon_foil.csv"
rm -f "$PROJECTS_DIR/falcon_design.wpa"
rm -f /home/ga/Documents/*.dat

# ------------------------------------------------------------------
# GENERATE DATA
# ------------------------------------------------------------------
# We embed S809 coordinates here to avoid network dependency issues.
# This is a standard S809 airfoil (subset of points for brevity/setup speed, 
# but enough to define the shape).

cat > /tmp/s809_raw.dat << 'EOF'
1.00000  0.00000
0.99639  0.00033
0.98565  0.00288
0.96822  0.00755
0.94443  0.01389
0.91468  0.02150
0.87943  0.03000
0.83925  0.03908
0.79485  0.04850
0.74697  0.05814
0.69636  0.06786
0.64379  0.07738
0.59005  0.08620
0.53587  0.09355
0.48192  0.09873
0.42878  0.10143
0.37691  0.10150
0.32684  0.09930
0.27909  0.09494
0.23419  0.08863
0.19266  0.08076
0.15486  0.07172
0.12111  0.06190
0.09172  0.05164
0.06692  0.04128
0.04678  0.03117
0.03126  0.02167
0.02035  0.01334
0.01431  0.00726
0.01210  0.00311
0.00000  0.00000
0.00065 -0.00085
0.00511 -0.00414
0.01278 -0.00806
0.02534 -0.01270
0.04368 -0.01799
0.06830 -0.02380
0.09941 -0.02995
0.13700 -0.03619
0.18084 -0.04217
0.23055 -0.04746
0.28562 -0.05156
0.34533 -0.05400
0.40885 -0.05436
0.47519 -0.05268
0.54323 -0.04918
0.61179 -0.04415
0.67961 -0.03801
0.74542 -0.03114
0.80800 -0.02391
0.86616 -0.01673
0.91866 -0.01007
0.96417 -0.00441
1.00000  0.00000
EOF

# Convert to "Corrupted" CSV format
# Format: Index,X_Pos,Y_Pos,Z_Pos,Notes
echo "Index,X_Pos,Y_Pos,Z_Pos,Notes" > "$INCOMING_DIR/project_falcon_foil.csv"
awk '{print (NR) "," $1 "," $2 ",0.0,RawExport"}' /tmp/s809_raw.dat >> "$INCOMING_DIR/project_falcon_foil.csv"

rm /tmp/s809_raw.dat

# Set ownership
chown -R ga:ga "$INCOMING_DIR"
chown -R ga:ga "$PROJECTS_DIR"

# ------------------------------------------------------------------
# SETUP APP
# ------------------------------------------------------------------
# Ensure QBlade is running
source /workspace/scripts/task_utils.sh
if ! is_qblade_running > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
fi

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="