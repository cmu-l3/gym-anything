#!/bin/bash
set -euo pipefail

echo "=== Setting up Policy Simulation Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
OUTPUT_DIR="/home/ga/Documents/gretl_output"
DATASET="food.gdt"

# Clean up previous runs
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Setup Gretl with food.gdt
setup_gretl_task "$DATASET" "policy_sim"

echo ""
echo "Task Setup Complete."
echo "Dataset $DATASET loaded."
echo "Output directory prepared at $OUTPUT_DIR"