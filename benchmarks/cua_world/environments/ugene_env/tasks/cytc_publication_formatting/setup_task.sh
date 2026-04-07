#!/bin/bash
echo "=== Setting up cytc_publication_formatting task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean any existing results directory
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Ensure the source data exists
if [ ! -f "/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta" ]; then
    echo "WARNING: Cytochrome C data missing, copying from assets..."
    cp /workspace/assets/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/
    chown ga:ga /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta
fi

# Make sure no stale instances of UGENE are running
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE via the user's environment script
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
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
    # Give UI time to fully render
    sleep 5
    
    # Dismiss any startup dialogs (like "Tip of the Day")
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot for evidence
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Task setup completed successfully."
else
    echo "ERROR: UGENE window failed to appear."
fi