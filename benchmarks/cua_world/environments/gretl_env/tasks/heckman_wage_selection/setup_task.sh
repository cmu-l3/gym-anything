#!/bin/bash
set -e
echo "=== Setting up Heckman Wage Selection Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf "/home/ga/Documents/gretl_output"
mkdir -p "/home/ga/Documents/gretl_output"
chown ga:ga "/home/ga/Documents/gretl_output"

# 2. Ensure mroz.gdt is available and clean
# mroz.gdt is a standard dataset in the POE5 package or system data
DATASET="mroz.gdt"
DATA_SRC=""

# Check potential locations
if [ -f "/opt/gretl_data/poe5/$DATASET" ]; then
    DATA_SRC="/opt/gretl_data/poe5/$DATASET"
elif [ -f "/usr/share/gretl/data/misc/$DATASET" ]; then
    DATA_SRC="/usr/share/gretl/data/misc/$DATASET"
elif [ -f "/home/ga/Documents/gretl_data/$DATASET" ]; then
    DATA_SRC="/home/ga/Documents/gretl_data/$DATASET"
fi

if [ -z "$DATA_SRC" ]; then
    echo "ERROR: $DATASET not found in standard locations."
    # Fallback: Create dummy if absolutely necessary, but we prefer real data
    # (In a real env, we'd ensure this file exists via install_gretl.sh)
    exit 1
fi

# Restore clean copy to Documents/gretl_data
mkdir -p "/home/ga/Documents/gretl_data"
cp "$DATA_SRC" "/home/ga/Documents/gretl_data/$DATASET"
chown ga:ga "/home/ga/Documents/gretl_data/$DATASET"

# 3. Launch Gretl with the dataset
setup_gretl_task "$DATASET" "heckman_task"

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Task Setup Complete ==="
echo "Dataset: $DATASET loaded."
echo "Goal: Estimate Heckman model and save output."