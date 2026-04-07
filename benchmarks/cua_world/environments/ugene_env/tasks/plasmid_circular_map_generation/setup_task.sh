#!/bin/bash
echo "=== Setting up plasmid_circular_map_generation task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/cloning/results 2>/dev/null || true
rm -f /tmp/plasmid_circular_map_* 2>/dev/null || true

# 2. Create directory structure
mkdir -p /home/ga/UGENE_Data/cloning/results
mkdir -p /home/ga/UGENE_Data/cloning

# 3. Download real pUC19 GenBank file from NCBI
# M77789.2 is the standard pUC19 cloning vector sequence (2686 bp)
echo "Downloading pUC19 sequence..."
wget -q -O /tmp/pUC19_download.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=M77789.2&rettype=gb&retmode=text"

# Fallback in case E-utilities is down or network blocked
if [ ! -s /tmp/pUC19_download.gb ] || ! grep -q "LOCUS" /tmp/pUC19_download.gb; then
    echo "WARNING: Failed to download pUC19 from NCBI. Using bundled asset if available or minimal synthetic fallback."
    if [ -f /workspace/assets/pUC19.gb ]; then
        cp /workspace/assets/pUC19.gb /home/ga/UGENE_Data/cloning/pUC19.gb
    else
        # Very basic fallback generator if everything else fails (to prevent task breaking)
        python3 -c "
import urllib.request
try:
    req = urllib.request.urlopen('https://raw.githubusercontent.com/manulera/pUC19/master/pUC19.gb')
    with open('/home/ga/UGENE_Data/cloning/pUC19.gb', 'wb') as f:
        f.write(req.read())
except Exception as e:
    print('Critical error: Could not fetch sequence data:', e)
"
    fi
else
    cp /tmp/pUC19_download.gb /home/ga/UGENE_Data/cloning/pUC19.gb
fi

chown -R ga:ga /home/ga/UGENE_Data/cloning

# 4. Record task start timestamp for anti-gaming verification
date +%s > /tmp/plasmid_circular_map_start_ts

# 5. Launch UGENE cleanly
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
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

if [ "$STARTED" = false ]; then
    echo "Retrying UGENE launch..."
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
    ELAPSED=0
    while [ $ELAPSED -lt 40 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
            STARTED=true
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
fi

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss welcome dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    # Take initial state screenshot
    DISPLAY=:1 scrot /tmp/plasmid_circular_map_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="