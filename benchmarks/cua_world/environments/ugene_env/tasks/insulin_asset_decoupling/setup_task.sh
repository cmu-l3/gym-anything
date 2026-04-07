#!/bin/bash
echo "=== Setting up insulin_asset_decoupling task ==="

# Clean up any previous task artifacts
rm -rf /home/ga/UGENE_Data/pipeline_assets 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data
chown -R ga:ga /home/ga/UGENE_Data

# Ensure the required source file exists
if [ ! -f /home/ga/UGENE_Data/human_insulin_gene.gb ]; then
    if [ -f /opt/ugene_data/human_insulin_gene.gb ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
        chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb
    else
        echo "WARNING: /opt/ugene_data/human_insulin_gene.gb not found. Attempting redownload."
        wget --timeout=30 -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" -O /home/ga/UGENE_Data/human_insulin_gene.gb || true
        chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb
    fi
fi

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Stop any existing UGENE instances cleanly
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# Start UGENE application as the 'ga' user
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

# Allow time for the UI to fully render
sleep 5

# Dismiss any potential welcome dialogs or tip of the day
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Capture initial state evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="