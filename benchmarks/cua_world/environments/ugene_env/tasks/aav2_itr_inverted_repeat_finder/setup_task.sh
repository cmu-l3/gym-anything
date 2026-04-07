#!/bin/bash
echo "=== Setting up aav2_itr_inverted_repeat_finder task ==="

# Clean old state
rm -rf /home/ga/UGENE_Data/gene_therapy 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/gene_therapy/results

# Download real AAV2 genome (NC_001401.2)
echo "Downloading AAV2 genome..."
wget --timeout=60 -q -O /home/ga/UGENE_Data/gene_therapy/aav2_genome.fasta "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_001401.2&rettype=fasta&retmode=text"

# Fallback if NCBI is down
if [ ! -s /home/ga/UGENE_Data/gene_therapy/aav2_genome.fasta ]; then
    echo "NCBI efetch failed, trying alternative sources..."
    wget --timeout=60 -q -O /home/ga/UGENE_Data/gene_therapy/aav2_genome.fasta "https://raw.githubusercontent.com/biopython/biopython/master/Tests/GenBank/NC_001401.fasta"
fi

chown -R ga:ga /home/ga/UGENE_Data/gene_therapy

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Start UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 5

# Maximize UGENE
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
    # Dismiss tips dialog
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="