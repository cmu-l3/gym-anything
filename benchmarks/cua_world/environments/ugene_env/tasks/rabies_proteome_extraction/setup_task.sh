#!/bin/bash
echo "=== Setting up rabies_proteome_extraction task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/virology 2>/dev/null || true
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/virology
mkdir -p /home/ga/UGENE_Data/results

# 2. Download Rabies Reference Genome (NC_001542.1)
echo "Downloading Rabies virus genome (NC_001542.1) from NCBI..."
wget -q "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_001542.1&rettype=gb&retmode=text" -O /home/ga/UGENE_Data/virology/rabies_virus_genome.gb

# Check if download succeeded
if [ ! -s /home/ga/UGENE_Data/virology/rabies_virus_genome.gb ]; then
    echo "WARNING: Download failed via wget. Trying curl..."
    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_001542.1&rettype=gb&retmode=text" > /home/ga/UGENE_Data/virology/rabies_virus_genome.gb
fi

if [ ! -s /home/ga/UGENE_Data/virology/rabies_virus_genome.gb ]; then
    echo "ERROR: Failed to fetch Rabies genome from NCBI."
    # If network fails completely, task will fail setup, which is expected for realistic tasks requiring live data fetching.
    exit 1
fi

echo "Successfully downloaded rabies_virus_genome.gb ($(stat -c%s /home/ga/UGENE_Data/virology/rabies_virus_genome.gb) bytes)"

# Set ownership
chown -R ga:ga /home/ga/UGENE_Data/virology
chown -R ga:ga /home/ga/UGENE_Data/results

# 3. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# 4. Kill existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 5. Launch UGENE as the agent user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window
TIMEOUT=90
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
    # Dismiss any startup dialogs (like tips)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi

    # Take initial screenshot for evidence
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window not detected. Continuing anyway..."
fi

echo "=== Task setup complete ==="