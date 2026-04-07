#!/bin/bash
echo "=== Setting up auto_mpg_regression task ==="

# Source shared utilities (do NOT use set -euo pipefail when sourcing)
source /workspace/scripts/task_utils.sh || { echo "FATAL: cannot source task_utils.sh"; exit 1; }

# Ensure the auto mpg dataset is in place
if [ ! -f /home/ga/Documents/datasets/auto_mpg.csv ]; then
    mkdir -p /home/ga/Documents/datasets
    cp /workspace/data/auto_mpg.csv /home/ga/Documents/datasets/auto_mpg.csv
    chown ga:ga /home/ga/Documents/datasets/auto_mpg.csv
fi

# Ensure output directory exists
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Standard task setup: kill old Octave, launch fresh, wait, dismiss dialogs, maximize
setup_octave_task "auto_mpg_regression"

echo "=== auto_mpg_regression task setup complete ==="
