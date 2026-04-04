#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up kernel_density_comparison task ==="

# 1. Define task variables
TASK_ID="kernel_density_comparison"
DATASET="food.gdt"
OUTPUT_DIR="/home/ga/Documents/gretl_output"

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous run artifacts
rm -f "$OUTPUT_DIR/group_stats.txt"
rm -f "$OUTPUT_DIR/kde_comparison.png"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# 4. Standard Gretl setup
# This kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "$DATASET" "$TASK_ID"

# 5. Additional Instructions / State Verification
echo "Gretl launched with $DATASET."
echo "Ready for analysis."

# Capture initial screenshot specific to this task setup check
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="