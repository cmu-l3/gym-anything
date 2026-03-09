#!/bin/bash
set -euo pipefail

echo "=== Setting up TSLS IV Estimation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure the output directory exists and is empty
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/*

# Ensure mroz.gdt is available
# If it's not in the standard location, try to find it in POE5 data
if [ ! -f "/home/ga/Documents/gretl_data/mroz.gdt" ]; then
    echo "Searching for mroz.gdt..."
    if [ -f "/opt/gretl_data/poe5/mroz.gdt" ]; then
        cp "/opt/gretl_data/poe5/mroz.gdt" "/home/ga/Documents/gretl_data/"
    elif [ -f "/usr/share/gretl/data/wooldridge/mroz.gdt" ]; then
        cp "/usr/share/gretl/data/wooldridge/mroz.gdt" "/home/ga/Documents/gretl_data/"
    else
        echo "WARNING: mroz.gdt not found in standard locations."
        # Fallback: create a dummy if strictly necessary, but for this task we rely on real data.
        # The environment installation script downloads POE5 data, so it should be there.
    fi
fi

# Use the utility to setup and launch Gretl with the dataset
setup_gretl_task "mroz.gdt" "tsls_task"

# Create a task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="
echo "Dataset: mroz.gdt"
echo "Target: TSLS estimation of lwage on educ (endogenous)"
echo "Instruments: mothereduc, fathereduc"