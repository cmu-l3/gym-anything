#!/bin/bash
set -e
echo "=== Setting up PDB Sequence Cross-Alignment Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Set up required directories
mkdir -p /home/ga/UGENE_Data/pdb_cross_alignment
# Clean any previous artifacts
rm -rf /home/ga/UGENE_Data/pdb_cross_alignment/*

# Ensure required data files are in place
if [ -f /opt/ugene_data/hemoglobin_4HHB.pdb ]; then
    cp /opt/ugene_data/hemoglobin_4HHB.pdb /home/ga/UGENE_Data/
else
    # Fallback to download if missing
    wget -qO /home/ga/UGENE_Data/hemoglobin_4HHB.pdb "https://files.rcsb.org/download/4HHB.pdb" || true
fi

if [ -f /opt/ugene_data/hemoglobin_beta_multispecies.fasta ]; then
    cp /opt/ugene_data/hemoglobin_beta_multispecies.fasta /home/ga/UGENE_Data/
elif [ -f /workspace/assets/hemoglobin_beta_multispecies.fasta ]; then
    cp /workspace/assets/hemoglobin_beta_multispecies.fasta /home/ga/UGENE_Data/
fi

# Fix permissions
chown -R ga:ga /home/ga/UGENE_Data

# Stop any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE as user ga
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

# Give UGENE time to fully initialize
sleep 5

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize and focus the window (CRITICAL for agent visibility)
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="