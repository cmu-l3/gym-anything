#!/bin/bash
echo "=== Setting up cross_taxa_consensus_extraction task ==="

# 1. Clean previous state and create directories
rm -rf /home/ga/UGENE_Data/evolution/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/evolution/results
mkdir -p /home/ga/UGENE_Data/evolution

# 2. Copy the diverse Cytochrome c sequences
# This data was downloaded during environment setup to /opt/ugene_data/cytochrome_c_multispecies.fasta
if [ -f /opt/ugene_data/cytochrome_c_multispecies.fasta ]; then
    cp /opt/ugene_data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/evolution/cytochrome_c_diverse.fasta
elif [ -f /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta ]; then
    cp /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/evolution/cytochrome_c_diverse.fasta
else
    echo "ERROR: Could not find cytochrome_c_multispecies.fasta!"
    exit 1
fi

chown -R ga:ga /home/ga/UGENE_Data/evolution

# 3. Record task start time
date +%s > /tmp/cross_taxa_start_ts

# 4. Launch UGENE and set up the window
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE to launch
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
    # Dismiss any welcome tips
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="