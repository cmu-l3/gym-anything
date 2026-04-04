#!/bin/bash
set -euo pipefail

echo "=== Setting up tobit_censored_script task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define dataset and paths
DATASET="mroz.gdt"
DATA_DIR="/home/ga/Documents/gretl_data"
OUTPUT_DIR="/home/ga/Documents/gretl_output"
MASTER_DATA="/opt/gretl_data/poe5"

# Ensure output directory exists and is empty of previous task artifacts
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/tobit_ols_comparison.txt"
rm -f "$OUTPUT_DIR/tobit_analysis.inp"
chown ga:ga "$OUTPUT_DIR"

# Ensure dataset is available
if [ ! -f "$DATA_DIR/$DATASET" ]; then
    echo "Checking master data for $DATASET..."
    if [ -f "$MASTER_DATA/$DATASET" ]; then
        cp "$MASTER_DATA/$DATASET" "$DATA_DIR/$DATASET"
        echo "Copied $DATASET from master."
    elif [ -f "/usr/share/gretl/data/mroz.gdt" ]; then
         cp "/usr/share/gretl/data/mroz.gdt" "$DATA_DIR/$DATASET"
         echo "Copied $DATASET from system share."
    else
        # Fallback: create minimal mroz-like dataset if absolutely necessary
        # But we expect the environment to have it. If missing, fail setup.
        echo "ERROR: $DATASET not found in known locations."
        # Attempt to download if network available (fallback)
        wget -q -O "$DATA_DIR/$DATASET" "https://github.com/skranz/gretl/raw/master/data/mroz.gdt" || true
    fi
fi

# Set permissions
chown ga:ga "$DATA_DIR/$DATASET"
chmod 644 "$DATA_DIR/$DATASET"

# Record setup state
date +%s > /tmp/task_start_time.txt
stat -c%Y "$DATA_DIR/$DATASET" > /tmp/dataset_mtime_initial.txt

# Launch Gretl with the dataset loaded
# This helps the agent start immediately without searching for files
echo "Launching Gretl with $DATASET..."
kill_gretl
launch_gretl "$DATA_DIR/$DATASET" "/home/ga/gretl_tobit_task.log"

# Wait for window and maximize
wait_for_gretl 30
maximize_gretl
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="