#!/bin/bash
echo "=== Setting up tb_katg_locus_extraction task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/UGENE_Data/tb_resistance_panel
chown -R ga:ga /home/ga/UGENE_Data/tb_resistance_panel

# Clean any previous artifacts
rm -f /home/ga/UGENE_Data/tb_resistance_panel/katG_locus.gb
rm -f /home/ga/UGENE_Data/tb_resistance_panel/extraction_report.txt
rm -f /tmp/katg_task_result.json

# Download the complete M. tuberculosis H37Rv genome (NC_000962.3) if it doesn't exist
GENOME_FILE="/home/ga/UGENE_Data/mtb_h37rv.gb"
if [ ! -s "$GENOME_FILE" ]; then
    echo "Downloading M. tuberculosis H37Rv genome from NCBI..."
    for i in {1..3}; do
        wget -qO "$GENOME_FILE" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_000962.3&rettype=gbwithparts&retmode=text"
        if grep -q "LOCUS" "$GENOME_FILE" 2>/dev/null; then
            echo "Successfully downloaded genome."
            break
        else
            echo "Download attempt $i failed. Retrying..."
            sleep 3
        fi
    done
fi

chown ga:ga "$GENOME_FILE"

# Start UGENE application
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
echo "Waiting for UGENE window..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 5

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Dismiss any popup dialogs via escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="