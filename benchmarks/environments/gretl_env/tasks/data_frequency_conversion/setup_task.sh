#!/bin/bash
set -e
echo "=== Setting up data_frequency_conversion task ==="

source /workspace/scripts/task_utils.sh

# Define dataset path
DATASET="usa.gdt"
DATASET_PATH="/home/ga/Documents/gretl_data/$DATASET"

# Ensure output directory is clean
rm -f /home/ga/Documents/gretl_output/usa_annual.csv
mkdir -p /home/ga/Documents/gretl_output

# Standard task setup: kill gretl, restore dataset, launch
# This utility function (defined in task_utils.sh) handles:
# - Killing existing instances
# - Restoring the .gdt file from /opt/gretl_data/poe5 to ensure it's clean
# - Launching Gretl with the file
# - Waiting for window, maximizing, focusing
setup_gretl_task "$DATASET" "freq_conversion"

# Record specific task start time for file timestamp verification
date +%s > /tmp/task_specific_start_time.txt

echo "=== Task setup complete ==="
echo "Dataset: $DATASET_PATH"
echo "Goal: Convert to Annual (1984-2008), calc Growth, Export CSV."