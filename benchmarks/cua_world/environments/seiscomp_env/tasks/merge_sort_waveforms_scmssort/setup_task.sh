#!/bin/bash
echo "=== Setting up merge_sort_waveforms_scmssort task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial SDS archive state for verification
find "$SEISCOMP_ROOT/var/lib/archive" -name "*.D.*" -type f > /tmp/initial_sds_files.txt
cat /tmp/initial_sds_files.txt | wc -l > /tmp/initial_sds_count.txt
echo "SDS archive contains $(cat /tmp/initial_sds_count.txt) miniSEED files"

# Extract station list from SDS for verification
cat /tmp/initial_sds_files.txt | xargs -I{} basename {} | cut -d. -f2 | sort -u > /tmp/expected_stations.txt
echo "Expected stations: $(cat /tmp/expected_stations.txt | tr '\n' ' ')"

# Remove any previous task output to ensure clean state
rm -f /home/ga/merged_waveforms.mseed
rm -f /home/ga/waveform_inventory.txt

# Ensure SeisComP environment is accessible
su - ga -c "source ~/.bashrc && which scmssort" > /tmp/scmssort_path.txt 2>/dev/null || echo "WARN: scmssort not found"

# Kill any existing terminal to start fresh
kill_seiscomp_gui "xterm"
sleep 1

# Launch a maximized terminal for the agent
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xterm -maximized -fa 'Monospace' -fs 11 -e bash" &
sleep 3

# Focus terminal
DISPLAY=:1 wmctrl -a "xterm" 2>/dev/null || true

# Take screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="