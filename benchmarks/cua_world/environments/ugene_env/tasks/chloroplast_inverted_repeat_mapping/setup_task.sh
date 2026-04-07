#!/bin/bash
set -e
echo "=== Setting up Chloroplast Inverted Repeat Mapping task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/botany/results 2>/dev/null || true
rm -f /tmp/cp_mapping_* 2>/dev/null || true

# 2. Create required directories
mkdir -p /home/ga/UGENE_Data/botany/results
mkdir -p /home/ga/UGENE_Data/botany

# 3. Download the real unannotated chloroplast genome (NC_000932.1)
echo "Downloading Arabidopsis thaliana chloroplast genome from NCBI..."
wget -q --timeout=60 "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_000932.1&rettype=fasta&retmode=text" -O /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta || true

# Verify download succeeded and is a valid FASTA file
if [ ! -s /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta ] || ! grep -q "^>" /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta; then
    echo "ERROR: Failed to download chloroplast genome from NCBI."
    # Create an obvious failure state file so it doesn't fail silently
    echo ">Download_Failed" > /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta
    echo "NNNNN" >> /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta
else
    # Strip any extra metadata from FASTA header to make it clean
    sed -i '1s/.*/>Arabidopsis_thaliana_chloroplast_genome/' /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta
    SEQ_LEN=$(grep -v "^>" /home/ga/UGENE_Data/botany/arabidopsis_cp.fasta | tr -d '\n' | wc -c)
    echo "Successfully downloaded genome: $SEQ_LEN bp"
fi

chown -R ga:ga /home/ga/UGENE_Data/botany

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch UGENE cleanly
pkill -f "ugene" 2>/dev/null || true
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

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss tips dialog if it pops up
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/cp_mapping_start.png 2>/dev/null || true
else
    echo "WARNING: UGENE window failed to appear during setup."
fi

echo "=== Task setup complete ==="