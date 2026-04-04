#!/bin/bash
set -euo pipefail

echo "=== Setting up recursive_forecast_loop task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the output directory exists and is empty/clean
OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Ensure the dataset usa.gdt is available in the documents folder
# (It might be in /opt/gretl_data/poe5/usa.gdt or similar)
DATASET="usa.gdt"
if [ -f "/opt/gretl_data/poe5/$DATASET" ]; then
    cp "/opt/gretl_data/poe5/$DATASET" "/home/ga/Documents/gretl_data/$DATASET"
    echo "Restored $DATASET from master copy."
elif [ ! -f "/home/ga/Documents/gretl_data/$DATASET" ]; then
    echo "ERROR: $DATASET not found in /opt or /home/ga/Documents/gretl_data"
    # Create a dummy if absolutely necessary, but strictly we should fail
    exit 1
fi

chown ga:ga "/home/ga/Documents/gretl_data/$DATASET"
chmod 644 "/home/ga/Documents/gretl_data/$DATASET"

# Launch Gretl with the dataset loaded
# This puts the agent in the correct starting state
setup_gretl_task "$DATASET" "recursive_forecast"

echo "=== Task setup complete ==="
echo "Dataset: $DATASET loaded"
echo "Goal: Write 'recursive_forecast.inp' to compute RMSFE via expanding window loop."