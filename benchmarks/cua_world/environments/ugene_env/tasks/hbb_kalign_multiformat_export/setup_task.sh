#!/bin/bash
echo "=== Setting up hbb_kalign_multiformat_export task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results

# Ensure input data exists
mkdir -p /home/ga/UGENE_Data
if [ ! -s /home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta ]; then
    if [ -s /opt/ugene_data/hemoglobin_beta_multispecies.fasta ]; then
        cp /opt/ugene_data/hemoglobin_beta_multispecies.fasta /home/ga/UGENE_Data/
    elif [ -s /workspace/assets/hemoglobin_beta_multispecies.fasta ]; then
        cp /workspace/assets/hemoglobin_beta_multispecies.fasta /home/ga/UGENE_Data/
    else
        echo "ERROR: Could not find hemoglobin input data."
        exit 1
    fi
fi

chown -R ga:ga /home/ga/UGENE_Data

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# 4. Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 5. Wait for UGENE window
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

    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true

    # Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 1
    fi

    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
    echo "Initial screenshot saved"
else
    echo "WARNING: UGENE window not detected, but proceeding."
fi

echo "=== Task setup complete ==="