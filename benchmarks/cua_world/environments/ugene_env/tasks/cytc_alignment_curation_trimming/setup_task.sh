#!/bin/bash
echo "=== Setting up cytc_alignment_curation_trimming task ==="

# 1. Clean previous task state
WORK_DIR="/home/ga/UGENE_Data/curated_alignment"
rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR"
chown -R ga:ga "$WORK_DIR"

# 2. Verify input data exists (Downloaded by UGENE env installation script)
INPUT_FASTA="/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta"
if [ ! -s "$INPUT_FASTA" ]; then
    echo "Cytochrome c FASTA file not found in home dir, copying from /opt/ugene_data..."
    cp /opt/ugene_data/cytochrome_c_multispecies.fasta "$INPUT_FASTA" 2>/dev/null || true
    chown ga:ga "$INPUT_FASTA"
fi

# Ensure 8 sequences exist
SEQ_COUNT=$(grep -c "^>" "$INPUT_FASTA" 2>/dev/null || echo "0")
echo "Input file has ${SEQ_COUNT} sequences"

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# 5. Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window to appear
TIMEOUT=60
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
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
    echo "Initial screenshot saved"
else
    echo "WARNING: UGENE failed to start cleanly"
fi

echo "=== Task setup complete ==="