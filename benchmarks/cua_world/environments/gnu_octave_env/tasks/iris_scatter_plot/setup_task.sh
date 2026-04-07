#!/bin/bash
echo "=== Setting up iris_scatter_plot task ==="

# Source shared utilities (do NOT use set -euo pipefail when sourcing)
source /workspace/scripts/task_utils.sh || { echo "FATAL: cannot source task_utils.sh"; exit 1; }

# Ensure the iris dataset is in place
if [ ! -f /home/ga/Documents/datasets/iris.csv ]; then
    mkdir -p /home/ga/Documents/datasets
    cp /workspace/data/iris.csv /home/ga/Documents/datasets/iris.csv
    chown ga:ga /home/ga/Documents/datasets/iris.csv
fi

# Ensure output directory exists
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Standard task setup: kill old Octave, launch fresh, wait, dismiss dialogs, maximize
setup_octave_task "iris_scatter_plot"

echo "=== iris_scatter_plot task setup complete ==="
