#!/bin/bash
echo "=== Setting up linear_restrictions_wage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the specific dataset required (cps5_small.gdt) is available
DATASET="cps5_small.gdt"
USER_DATA_DIR="/home/ga/Documents/gretl_data"
MASTER_DATA_DIR="/opt/gretl_data/poe5"

mkdir -p "$USER_DATA_DIR"

if [ -f "$MASTER_DATA_DIR/$DATASET" ]; then
    echo "Copying $DATASET from master data..."
    cp "$MASTER_DATA_DIR/$DATASET" "$USER_DATA_DIR/$DATASET"
elif [ -f "/usr/share/gretl/data/poe5/$DATASET" ]; then
    cp "/usr/share/gretl/data/poe5/$DATASET" "$USER_DATA_DIR/$DATASET"
else
    # Fallback: create a dummy if real data missing (should be there from env setup)
    echo "WARNING: $DATASET not found in master locations. Checking if already in user dir."
fi

# Ensure permissions
chown -R ga:ga "/home/ga/Documents"

# Setup Gretl with this specific dataset
setup_gretl_task "$DATASET" "linear_restrictions"

# Display instructions overlay or text (simulated by echo here)
echo ""
echo "Task Ready: Restricted Least Squares on Wage Data"
echo "Dataset: $DATASET"
echo "Goal: Estimate model lwage = b0 + b1*educ + b2*exper"
echo "Restriction: b1 (educ) = 0.1"