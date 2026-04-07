#!/bin/bash
# Export result for fitts_throughput_analysis
# Copies files to /tmp for easy retrieval by the verifier using copy_from_env

set -e
echo "=== Exporting fitts_throughput_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/fitts_final_screenshot.png 2>/dev/null || true

# Copy data to /tmp to avoid permission issues during verification
cp /home/ga/pebl/data/fitts_data.csv /tmp/fitts_data_copy.csv 2>/dev/null || true
chmod 644 /tmp/fitts_data_copy.csv 2>/dev/null || true

echo "=== fitts_throughput_analysis export complete ==="