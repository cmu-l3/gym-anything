#!/bin/bash
echo "=== Setting up hiv_drug_target_extraction task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean any existing artifacts
rm -rf /home/ga/UGENE_Data/virology 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/virology/targets

# Download the authentic HIV-1 reference genome (NC_001802.1) directly from NCBI
echo "Downloading HIV-1 Reference Genome (NC_001802.1)..."
wget -qO /home/ga/UGENE_Data/virology/HIV1_reference.gb \
  "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_001802.1&rettype=gbwithparts&retmode=text"

# Verify download succeeded; provide fallback alert if NCBI is unreachable
if [ ! -s /home/ga/UGENE_Data/virology/HIV1_reference.gb ]; then
    echo "ERROR: Could not download HIV-1 reference genome from NCBI. Please check network connectivity."
    exit 1
fi

# Set permissions
chown -R ga:ga /home/ga/UGENE_Data/virology

# Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
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
    
    # Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot showing clean state
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot saved."
else
    echo "WARNING: UGENE failed to start properly."
fi

echo "=== Task setup complete ==="