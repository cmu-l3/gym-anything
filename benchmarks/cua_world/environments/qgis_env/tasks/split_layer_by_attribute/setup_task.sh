#!/bin/bash
echo "=== Setting up split_layer_by_attribute task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
DATA_DIR="/home/ga/GIS_Data"
INPUT_FILE="$DATA_DIR/ne_110m_admin_0_countries.geojson"
OUTPUT_DIR="$DATA_DIR/exports/countries_by_continent"

# Create output directory and ensure it's empty
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*
chown -R ga:ga "$OUTPUT_DIR"

# Download the Natural Earth dataset if not present
if [ ! -f "$INPUT_FILE" ]; then
    echo "Downloading Natural Earth countries dataset..."
    # Use a reliable source for the GeoJSON
    wget -q -O "$INPUT_FILE" "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson" || \
    curl -L -o "$INPUT_FILE" "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"
    
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: Failed to download input data."
        exit 1
    fi
    chown ga:ga "$INPUT_FILE"
fi

# Verify input file validity
echo "Verifying input data..."
python3 -c "import json; print(len(json.load(open('$INPUT_FILE'))['features']))" > /tmp/input_feature_count.txt 2>&1
echo "Input contains $(cat /tmp/input_feature_count.txt) features"

# 2. Record Baseline State
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_file_count

# 3. Launch QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 45
sleep 2

# Maximize and focus
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Take Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Task: Split '$INPUT_FILE' by field 'CONTINENT'"
echo "Output Directory: '$OUTPUT_DIR'"