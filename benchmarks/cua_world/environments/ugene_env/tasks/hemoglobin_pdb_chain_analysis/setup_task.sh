#!/bin/bash
echo "=== Setting up hemoglobin_pdb_chain_analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean any previous results
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results

# Ensure the 4HHB PDB file is available
# It should have been downloaded by the environment install script, but we ensure it exists
if [ ! -f /home/ga/UGENE_Data/hemoglobin_4HHB.pdb ]; then
    echo "PDB file not found in user directory, copying from /opt or downloading..."
    if [ -f /opt/ugene_data/hemoglobin_4HHB.pdb ]; then
        cp /opt/ugene_data/hemoglobin_4HHB.pdb /home/ga/UGENE_Data/
    else
        wget --timeout=60 -q "https://files.rcsb.org/download/4HHB.pdb" -O /home/ga/UGENE_Data/hemoglobin_4HHB.pdb || true
    fi
fi

chown -R ga:ga /home/ga/UGENE_Data/results
chown ga:ga /home/ga/UGENE_Data/hemoglobin_4HHB.pdb

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE as the user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Configure the window
if [ "$STARTED" = true ]; then
    sleep 5 # Let UI fully load
    
    # Dismiss any "Tip of the day" or update dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus UGENE
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot to prove starting state
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="