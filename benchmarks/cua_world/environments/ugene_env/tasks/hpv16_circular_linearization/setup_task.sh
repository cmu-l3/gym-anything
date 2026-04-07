#!/bin/bash
set -e
echo "=== Setting up hpv16_circular_linearization task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/hpv 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/hpv/results

# 2. Download the real HPV16 reference genome (NC_001526.4) from NCBI
echo "Downloading HPV16 reference genome from NCBI E-Utilities..."
DOWNLOAD_SUCCESS=false

for i in {1..3}; do
    wget --timeout=60 -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_001526.4&rettype=gb&retmode=text" -O /home/ga/UGENE_Data/hpv/hpv16_reference.gb
    
    if [ -s /home/ga/UGENE_Data/hpv/hpv16_reference.gb ] && grep -q "LOCUS" /home/ga/UGENE_Data/hpv/hpv16_reference.gb; then
        echo "Successfully downloaded HPV16 reference genome."
        DOWNLOAD_SUCCESS=true
        break
    fi
    echo "Download attempt $i failed, retrying..."
    sleep 3
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "ERROR: Failed to download HPV16 genome. Task cannot proceed without real biological data."
    exit 1
fi

chown -R ga:ga /home/ga/UGENE_Data/hpv

# 3. Record task start time (anti-gaming)
date +%s > /tmp/hpv16_task_start_ts

# 4. Ensure UGENE is ready
pkill -f "ugene" 2>/dev/null || true
sleep 2

echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

# Give UI time to initialize
sleep 5

# Maximize UGENE window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/hpv16_task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="