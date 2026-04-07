#!/bin/bash
set -e
echo "=== Setting up insulin_promoter_tfbs_jaspar task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create clean results directory
rm -rf /home/ga/UGENE_Data/tfbs_results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/tfbs_results
chown -R ga:ga /home/ga/UGENE_Data/tfbs_results

# Ensure input data exists (copy from opt if missing from home)
if [ ! -f "/home/ga/UGENE_Data/human_insulin_gene.gb" ]; then
    if [ -f "/opt/ugene_data/human_insulin_gene.gb" ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
        chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb
    else
        echo "WARNING: human_insulin_gene.gb not found in /opt either!"
    fi
fi

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE via wrapper
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
    echo "UGENE window detected."
    sleep 5
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
else
    echo "WARNING: UGENE window did not appear."
fi

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="