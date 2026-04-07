#!/bin/bash
echo "=== Setting up cytochrome_c_distance_matrix task ==="

# Clean results directory
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Ensure the FASTA file exists
if [ ! -f "/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta" ]; then
    # Fallback if not copied properly
    cp /workspace/assets/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta 2>/dev/null || true
fi
chown ga:ga /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
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
    sleep 4
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
    sleep 1
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
    echo "Task setup complete, screenshot saved."
else
    echo "WARNING: UGENE window did not appear."
fi