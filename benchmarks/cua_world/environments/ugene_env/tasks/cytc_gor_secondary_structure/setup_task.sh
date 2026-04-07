#!/bin/bash
echo "=== Setting up cytc_gor_secondary_structure task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results/cytc_structure 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results/cytc_structure

# Ensure the cytochrome_c_multispecies.fasta file is present
if [ ! -f "/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta" ]; then
    if [ -f "/opt/ugene_data/cytochrome_c_multispecies.fasta" ]; then
        cp /opt/ugene_data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/
    elif [ -f "/workspace/assets/cytochrome_c_multispecies.fasta" ]; then
        cp /workspace/assets/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/
    else
        echo "WARNING: Could not find cytochrome_c_multispecies.fasta source file"
    fi
fi

chown -R ga:ga /home/ga/UGENE_Data

# 2. Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 3. Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 4. Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot showing correct initial state
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
else
    echo "ERROR: UGENE failed to start"
fi

echo "=== Task setup complete ==="