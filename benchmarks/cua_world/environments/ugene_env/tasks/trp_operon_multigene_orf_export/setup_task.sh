#!/bin/bash
set -e
echo "=== Setting up trp_operon_multigene_orf_export task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/UGENE_Data/ecoli_trp_operon/results
chown -R ga:ga /home/ga/UGENE_Data/ecoli_trp_operon

# Download real GenBank record for E. coli trp operon (V00368.1)
echo "Downloading E. coli trp operon GenBank file..."
curl -sL "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=V00368.1&rettype=gbwithparts&retmode=text" -o /home/ga/UGENE_Data/ecoli_trp_operon/trp_operon.gb

# Verify download
if [ ! -s /home/ga/UGENE_Data/ecoli_trp_operon/trp_operon.gb ] || ! grep -q "LOCUS" /home/ga/UGENE_Data/ecoli_trp_operon/trp_operon.gb; then
    echo "Download failed. Fetching fallback data..."
    # Fallback to efetch via wget
    wget -qO /home/ga/UGENE_Data/ecoli_trp_operon/trp_operon.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=V00368.1&rettype=gbwithparts&retmode=text" || true
fi

chown ga:ga /home/ga/UGENE_Data/ecoli_trp_operon/trp_operon.gb

# Ensure UGENE is running
echo "Starting UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

sleep 5

# Maximize UGENE
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="