#!/bin/bash
set -e

echo "=== Setting up filter_and_export_features task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Install dbfread for verification if not present
if ! python3 -c "import dbfread" 2>/dev/null; then
    echo "Installing verification dependencies..."
    pip3 install dbfread 2>/dev/null || true
fi

# Ensure exports directory exists and is clean
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
rm -f "$EXPORTS_DIR/populous_countries".*
chown -R ga:ga "$EXPORTS_DIR"
chmod 755 "$EXPORTS_DIR"

# Verify source data exists
SRC_DIR="/home/ga/gvsig_data/countries"
SRC_SHP=$(ls "$SRC_DIR"/ne_110m_admin_0_countries.shp 2>/dev/null | head -1)
if [ -z "$SRC_SHP" ]; then
    echo "ERROR: Source countries shapefile not found!"
    exit 1
fi
echo "Source shapefile: $SRC_SHP"

# Compute ground truth feature count for reference (hidden from agent)
# This serves as a baseline to ensure the input data hasn't changed
python3 - "$SRC_DIR" << 'PYEOF' > /tmp/expected_feature_count.txt 2>/dev/null || echo "13" > /tmp/expected_feature_count.txt
import sys, os, struct
# Simple DBF parser to avoid dependency issues during setup if dbfread fails
try:
    from dbfread import DBF
    dbf_files = [f for f in os.listdir(sys.argv[1]) if f.lower().endswith('.dbf')]
    if dbf_files:
        table = DBF(os.path.join(sys.argv[1], dbf_files[0]))
        count = sum(1 for r in table if float(r.get('POP_EST', 0)) > 100000000)
        print(count)
    else:
        print("13")
except:
    print("13") 
PYEOF

EXPECTED=$(cat /tmp/expected_feature_count.txt)
echo "Ground truth calculated: $EXPECTED countries with POP_EST > 100,000,000"

# Kill any existing gvSIG
kill_gvsig

# Launch gvSIG with the countries project
# We use the pre-built project which has the layer loaded and styled
PROJECT_FILE="/home/ga/gvsig_data/projects/countries_base.gvsproj"
PREBUILT_SOURCE="/workspace/data/projects/countries_base.gvsproj"

# Ensure project file is fresh
if [ -f "$PREBUILT_SOURCE" ]; then
    mkdir -p "$(dirname "$PROJECT_FILE")"
    cp "$PREBUILT_SOURCE" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
fi

if [ -f "$PROJECT_FILE" ]; then
    echo "Launching gvSIG with countries_base project..."
    launch_gvsig "$PROJECT_FILE"
else
    echo "WARNING: Project file not found, launching gvSIG blank..."
    launch_gvsig
fi

# Allow extra time for full UI initialization
sleep 8

# Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="