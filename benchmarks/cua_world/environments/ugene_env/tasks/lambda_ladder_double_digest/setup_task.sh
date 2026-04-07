#!/bin/bash
set -e
echo "=== Setting up lambda_ladder_double_digest task ==="

# 1. Clean previous state and set up directories
rm -rf /home/ga/UGENE_Data/lambda_phage 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/lambda_phage/results
mkdir -p /home/ga/UGENE_Data/lambda_phage

# 2. Download the Lambda Phage Genome (J02459.1) from NCBI
echo "Downloading Lambda Phage reference genome (J02459.1)..."
GENOME_FILE="/home/ga/UGENE_Data/lambda_phage/lambda_genome.gb"

# Try eutils fetch first
curl -sS -o "$GENOME_FILE" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=J02459.1&rettype=gb&retmode=text" || true

# Validate download
if [ ! -s "$GENOME_FILE" ] || ! grep -q "LOCUS" "$GENOME_FILE"; then
    echo "Primary download failed. Attempting fallback..."
    curl -sS -L -o "$GENOME_FILE" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_001416.1&rettype=gb&retmode=text" || true
fi

if [ ! -s "$GENOME_FILE" ] || ! grep -q "LOCUS" "$GENOME_FILE"; then
    echo "CRITICAL ERROR: Failed to download real Lambda phage genome."
    exit 1
fi

chown -R ga:ga /home/ga/UGENE_Data/lambda_phage

# 3. Record start time (anti-gaming)
date +%s > /tmp/lambda_task_start_ts

# 4. Launch UGENE
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 5. Wait for UGENE window
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
    # Dismiss tips/dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Focus and maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Capture initial screenshot
    DISPLAY=:1 scrot /tmp/lambda_task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="