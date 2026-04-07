#!/bin/bash
set -e
echo "=== Setting up insulin_mature_chain_extraction task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state for output directory
rm -rf /home/ga/UGENE_Data/chains 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/chains
chown -R ga:ga /home/ga/UGENE_Data/chains

# Ensure the insulin GenBank file exists
if [ ! -s /home/ga/UGENE_Data/human_insulin_gene.gb ]; then
    echo "Copying human insulin GenBank file to working directory..."
    if [ -s /opt/ugene_data/human_insulin_gene.gb ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/
    else
        echo "WARNING: Pre-downloaded insulin GenBank missing. Fetching from NCBI..."
        wget --timeout=60 -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" -O /home/ga/UGENE_Data/human_insulin_gene.gb || true
    fi
    chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb
fi

# Close any running UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# Launch UGENE as the ga user
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
TIMEOUT=60
ELAPSED=0
UGENE_READY=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        UGENE_READY=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$UGENE_READY" = true ]; then
    sleep 5 # Allow UI to fully render

    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 1
    fi

    # Dismiss tips or dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true

    # Capture initial setup evidence
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "UGENE initialized and screenshot captured."
else
    echo "WARNING: UGENE window failed to appear."
fi

echo "=== Setup complete ==="