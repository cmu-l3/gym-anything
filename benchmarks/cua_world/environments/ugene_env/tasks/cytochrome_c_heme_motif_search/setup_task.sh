#!/bin/bash
echo "=== Setting up cytochrome_c_heme_motif_search task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean any existing results to ensure a fresh state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Ensure target FASTA is available in the expected directory
if [ -f "/opt/ugene_data/cytochrome_c_multispecies.fasta" ] && [ ! -f "/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta" ]; then
    cp /opt/ugene_data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/
    chown ga:ga /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta
fi

# Stop any currently running UGENE processes
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE as the ga user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear (up to 60 seconds)
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
    echo "UGENE started successfully."
    sleep 5  # Give UI time to stabilize
    
    # Dismiss any welcome tips / startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    
    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot for evidence
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="