#!/bin/bash
set -euo pipefail

echo "=== Setting up Logit Marginal Effects task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Define dataset location
DATASET="mroz.gdt"
USER_DATA_DIR="/home/ga/Documents/gretl_data"
OUTPUT_DIR="/home/ga/Documents/gretl_output"

# 2. Ensure dataset is available
if [ ! -f "$USER_DATA_DIR/$DATASET" ]; then
    echo "Copying $DATASET..."
    # Try common locations defined in environment setup
    if [ -f "/opt/gretl_data/poe5/$DATASET" ]; then
        cp "/opt/gretl_data/poe5/$DATASET" "$USER_DATA_DIR/$DATASET"
    elif [ -f "/usr/share/gretl/data/wooldridge/$DATASET" ]; then
        cp "/usr/share/gretl/data/wooldridge/$DATASET" "$USER_DATA_DIR/$DATASET"
    else
        # Fallback: Create minimal mroz dataset if missing (unlikely in this env, but safe)
        echo "WARNING: mroz.gdt not found in standard paths."
    fi
fi

# Ensure permissions
chown -R ga:ga "$USER_DATA_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# 3. Clean up previous results
rm -f "$OUTPUT_DIR/logit_mfx.txt"

# 4. Standard Gretl setup (kill existing, launch with dataset)
setup_gretl_task "$DATASET" "logit_task"

# 5. Additional instruction display (optional, helpful for agent)
echo "Task Setup Complete"
echo "Dataset: $DATASET loaded."
echo "Goal: Estimate Logit (lfp ~ const educ exper age kidslt6) and save Marginal Effects."