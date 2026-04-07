#!/bin/bash
echo "=== Setting up earthquake_magnitude_analysis task ==="

# Source shared utilities (do NOT use set -euo pipefail when sourcing)
source /workspace/scripts/task_utils.sh || { echo "FATAL: cannot source task_utils.sh"; exit 1; }

# Ensure the earthquake dataset is in place
if [ ! -f /home/ga/Documents/datasets/earthquakes_2024_jan.csv ]; then
    mkdir -p /home/ga/Documents/datasets
    cp /workspace/data/earthquakes_2024_jan.csv /home/ga/Documents/datasets/earthquakes_2024_jan.csv
    chown ga:ga /home/ga/Documents/datasets/earthquakes_2024_jan.csv
fi

# Ensure output directory exists
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Standard task setup: kill old Octave, launch fresh, wait, dismiss dialogs, maximize
setup_octave_task "earthquake_magnitude_analysis"

echo "=== earthquake_magnitude_analysis task setup complete ==="
