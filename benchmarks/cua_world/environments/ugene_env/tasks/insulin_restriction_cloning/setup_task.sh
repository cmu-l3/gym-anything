#!/bin/bash
set -e
echo "=== Setting up insulin_restriction_cloning task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure results directory is clean and exists
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Verify input data exists (fallback to download if missing)
INPUT_FILE="/home/ga/UGENE_Data/human_insulin_gene.gb"
if [ ! -s "$INPUT_FILE" ]; then
    echo "WARNING: Human insulin GenBank file not found, downloading..."
    wget --timeout=60 -q \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" \
        -O "$INPUT_FILE" || true
    chown ga:ga "$INPUT_FILE"
fi

if [ ! -s "$INPUT_FILE" ]; then
    echo "FATAL: Cannot obtain insulin gene data"
    exit 1
fi

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# Launch UGENE with the insulin file loaded
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh '$INPUT_FILE' &"

# Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Give the UI time to fully load the sequence and render the view
sleep 8

# Dismiss any popup dialogs/tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Take initial screenshot of the starting state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="