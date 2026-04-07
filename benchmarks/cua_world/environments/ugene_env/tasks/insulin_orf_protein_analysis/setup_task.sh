#!/bin/bash
set -e
echo "=== Setting up insulin_orf_protein_analysis task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories and ensure they are clean
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# Ensure the human insulin GenBank file exists
if [ ! -s /home/ga/UGENE_Data/human_insulin_gene.gb ]; then
    echo "Insulin GenBank file not found in user directory. Copying from opt/assets..."
    if [ -s /opt/ugene_data/human_insulin_gene.gb ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
    elif [ -s /workspace/assets/human_insulin_gene.gb ]; then
        cp /workspace/assets/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
    else
        # Fallback to downloading it if completely missing
        wget -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" -O /home/ga/UGENE_Data/human_insulin_gene.gb || true
    fi
fi
chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb

# Stop any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE as the ga user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
echo "Waiting for UGENE window..."
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
    sleep 5 # Allow UI to fully render
    
    # Dismiss any startup tips or welcome dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the window to ensure agent visibility
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi

    # Pre-load the human_insulin_gene.gb file using Ctrl+O
    echo "Loading human_insulin_gene.gb..."
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    
    # Type file path and hit Enter
    # In some dialogs, focus might not be directly on the text field, but ctrl+l usually focuses the path bar in GTK, or just typing works in standard Qt dialogs.
    DISPLAY=:1 xdotool type --clearmodifiers '/home/ga/UGENE_Data/human_insulin_gene.gb'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 3
    
    # Ensure it's fully maximized and loaded
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
    
    # Take initial screenshot for evidence
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window did not appear within timeout."
fi

echo "=== Task setup complete ==="