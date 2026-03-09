#!/bin/bash
set -e
echo "=== Setting up Poisson Fertility Modeling Task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/*

# Ensure mroz.gdt is available (it's a standard dataset, usually in POE5 or built-in)
# We try to copy it from the master data dir to the user dir if not present
DATASET="mroz.gdt"
DATA_SOURCE="/opt/gretl_data/poe5/$DATASET"
USER_DATA="/home/ga/Documents/gretl_data/$DATASET"

if [ ! -f "$USER_DATA" ]; then
    if [ -f "$DATA_SOURCE" ]; then
        echo "Copying $DATASET from master archive..."
        cp "$DATA_SOURCE" "$USER_DATA"
    else
        # Fallback: Create it or try to find it elsewhere
        echo "Searching for $DATASET..."
        FOUND=$(find /usr/share/gretl -name "$DATASET" | head -n 1)
        if [ -n "$FOUND" ]; then
            cp "$FOUND" "$USER_DATA"
        else
            echo "WARNING: $DATASET not found. Task may fail if agent cannot find data."
        fi
    fi
fi
chown ga:ga "$USER_DATA"

# Standard Gretl launch sequence
setup_gretl_task "$DATASET" "poisson_task"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="