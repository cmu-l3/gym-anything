#!/bin/bash
echo "=== Setting up HIV Frameshift Annotation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/UGENE_Data/virology/results
rm -rf /home/ga/UGENE_Data/virology/results/* 2>/dev/null || true

# Download the real HIV-1 reference genome (NC_001802.1)
echo "Downloading HIV-1 Reference Genome..."
HIV_FILE="/home/ga/UGENE_Data/virology/hiv_genome.gb"

wget --timeout=30 -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_001802.1&rettype=gb&retmode=text" -O "$HIV_FILE"

# Fallback to alternate accession if NC_001802 fails
if [ ! -s "$HIV_FILE" ]; then
    echo "Primary download failed, trying alternate HIV-1 isolate..."
    wget --timeout=30 -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=AF033819.3&rettype=gb&retmode=text" -O "$HIV_FILE"
fi

# Ensure permissions are correct
chown -R ga:ga /home/ga/UGENE_Data/virology

# Launch UGENE
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2

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

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup tips/dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot proving starting state
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window not detected during setup."
fi

echo "=== Task setup complete ==="