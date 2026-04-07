#!/bin/bash
echo "=== Setting up Workflow Designer Pipeline Task ==="

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Clean and setup directories
rm -rf /home/ga/UGENE_Data/workflow_results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/workflow_results
chown -R ga:ga /home/ga/UGENE_Data/workflow_results

# 3. Ensure input data exists
INPUT_FILE="/home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta"
if [ ! -s "$INPUT_FILE" ]; then
    echo "Restoring input FASTA file from base environment..."
    mkdir -p /home/ga/UGENE_Data/
    cp /opt/ugene_data/hemoglobin_beta_multispecies.fasta "$INPUT_FILE" 2>/dev/null || \
    cp /workspace/assets/hemoglobin_beta_multispecies.fasta "$INPUT_FILE" 2>/dev/null || true
    chown ga:ga "$INPUT_FILE"
fi

SEQ_COUNT=$(grep -c "^>" "$INPUT_FILE" 2>/dev/null || echo "0")
echo "Input file verified: ${SEQ_COUNT} sequences"

# 4. Stop existing instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# 5. Launch UGENE
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window
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
    sleep 5 # Wait for full UI render
    
    # Dismiss any startup dialogs (like Tips)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Focus and maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 1
    fi
    
    # Take initial state screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Task environment initialized and captured."
else
    echo "WARNING: UGENE window not detected."
fi

echo "=== Task setup complete ==="