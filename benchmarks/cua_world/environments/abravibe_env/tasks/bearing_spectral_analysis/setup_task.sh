#!/bin/bash
echo "=== Setting up bearing_spectral_analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "FATAL: cannot source task_utils.sh"; exit 1; }

# Ensure CWRU data files are in place
for f in normal_97.mat ir007_105.mat; do
    if [ ! -f "/home/ga/Documents/cwru_data/$f" ]; then
        mkdir -p /home/ga/Documents/cwru_data
        cp "/workspace/data/$f" "/home/ga/Documents/cwru_data/$f"
        chown ga:ga "/home/ga/Documents/cwru_data/$f"
    fi
done

# Ensure output directory exists
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Standard task setup: kill old Octave, launch fresh, wait, dismiss dialogs, maximize
setup_octave_task "bearing_spectral_analysis"

# Set Octave working directory to cwru_data so files are visible in the file browser
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "cd('/home/ga/Documents/cwru_data');" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
sleep 2

echo "=== bearing_spectral_analysis task setup complete ==="
