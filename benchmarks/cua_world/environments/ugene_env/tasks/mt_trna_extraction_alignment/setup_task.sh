#!/bin/bash
echo "=== Setting up mt_trna_extraction_alignment task ==="

# 1. Clean previous state and create directories
rm -rf /home/ga/UGENE_Data/mitochondria 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/mitochondria/results
chown -R ga:ga /home/ga/UGENE_Data/mitochondria

# 2. Download Real Data (Human Mitochondrial Genome NC_012920.1)
echo "Downloading NC_012920.1 from NCBI..."
curl -sS --retry 3 "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_012920.1&rettype=gb&retmode=text" -o /home/ga/UGENE_Data/mitochondria/human_mtDNA.gb

if ! grep -q "LOCUS" /home/ga/UGENE_Data/mitochondria/human_mtDNA.gb; then
    echo "ERROR: Download failed or invalid file."
    exit 1
fi
echo "Downloaded human_mtDNA.gb successfully."

chown ga:ga /home/ga/UGENE_Data/mitochondria/human_mtDNA.gb

# 3. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# 4. Kill existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 5. Launch UGENE and wait for it
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

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
    
    # Open the sequence automatically to set up the perfect starting state
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers '/home/ga/UGENE_Data/mitochondria/human_mtDNA.gb'
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 4
    
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
    echo "Task setup complete and screenshot captured."
else
    echo "WARNING: UGENE failed to launch in the expected time."
fi