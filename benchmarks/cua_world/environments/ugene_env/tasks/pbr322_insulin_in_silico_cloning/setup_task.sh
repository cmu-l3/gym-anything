#!/bin/bash
set -e
echo "=== Setting up pBR322 In Silico Cloning Task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results

# 2. Ensure the source human insulin gene file is present
# (The environment setup script downloads this, but we verify and copy to ensure it's clean)
if [ ! -f "/home/ga/UGENE_Data/human_insulin_gene.gb" ]; then
    echo "Warning: human_insulin_gene.gb not found in /home/ga/UGENE_Data/"
    if [ -f "/opt/ugene_data/human_insulin_gene.gb" ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/
    else
        # Fallback to direct download if missing
        wget --timeout=60 -q \
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" \
            -O /home/ga/UGENE_Data/human_insulin_gene.gb || true
    fi
fi

chown -R ga:ga /home/ga/UGENE_Data

# 3. Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 4. Kill any existing UGENE instances
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
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup dialogs (like Tips)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="