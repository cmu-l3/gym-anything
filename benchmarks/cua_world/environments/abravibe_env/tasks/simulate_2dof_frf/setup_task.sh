#!/bin/bash
echo "=== Setting up simulate_2dof_frf task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "FATAL: cannot source task_utils.sh"; exit 1; }

# Ensure output directory exists
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Standard task setup: kill old Octave, launch fresh, wait, dismiss dialogs, maximize
setup_octave_task "simulate_2dof_frf"

echo "=== simulate_2dof_frf task setup complete ==="
