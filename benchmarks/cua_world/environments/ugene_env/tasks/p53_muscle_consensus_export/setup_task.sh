#!/bin/bash
echo "=== Setting up p53_muscle_consensus_export task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous task state
rm -rf /home/ga/UGENE_Data/p53 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/p53/results

# Download real p53 ortholog sequences from UniProt
P53_ACCESSIONS="P04637,P02340,P10361,P10360,P07193,P79734,Q29537,P67939"
echo "Downloading p53 sequences..."
wget --timeout=120 -q \
    "https://rest.uniprot.org/uniprotkb/stream?query=accession:${P53_ACCESSIONS}&format=fasta" \
    -O /home/ga/UGENE_Data/p53/p53_orthologs.fasta

# Verify download
if [ ! -s /home/ga/UGENE_Data/p53/p53_orthologs.fasta ]; then
    echo "ERROR: Failed to download sequences from UniProt"
    exit 1
fi

SEQ_COUNT=$(grep -c "^>" /home/ga/UGENE_Data/p53/p53_orthologs.fasta)
echo "Downloaded ${SEQ_COUNT} p53 sequences"

# Ensure proper ownership
chown -R ga:ga /home/ga/UGENE_Data/p53

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# Launch UGENE as the ga user
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
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 1
    fi

    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
    echo "Initial screenshot captured"
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="