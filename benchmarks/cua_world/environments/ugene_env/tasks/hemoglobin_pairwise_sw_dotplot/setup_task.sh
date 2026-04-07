#!/bin/bash
echo "=== Setting up hemoglobin_pairwise_sw_dotplot task ==="

# Clean previous task state and create fresh output directory
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Verify input data exists
if [ ! -s /home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta ]; then
    echo "ERROR: Hemoglobin beta FASTA file not found or empty"
    exit 1
fi

SEQ_COUNT=$(grep -c "^>" /home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta 2>/dev/null || echo "0")
echo "Input file has ${SEQ_COUNT} sequences"

# Record task start time for verification (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
TIMEOUT=90
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = false ]; then
    echo "WARNING: UGENE window not detected, retrying launch..."
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

    ELAPSED=0
    while [ $ELAPSED -lt 60 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
            echo "UGENE window detected on retry after ${ELAPSED}s"
            STARTED=true
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
fi

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

    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot saved"
else
    echo "ERROR: UGENE failed to start"
fi

echo "=== Task setup complete ==="