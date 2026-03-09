#!/bin/bash
echo "=== Setting up vaccine_epitope_conservation task ==="

# Step 1: CLEAN
rm -rf /home/ga/UGENE_Data/vaccine/results 2>/dev/null || true
rm -f /tmp/vaccine_epitope_conservation_* 2>/dev/null || true

# Step 2: Create directories
mkdir -p /home/ga/UGENE_Data/vaccine/results
mkdir -p /home/ga/UGENE_Data/vaccine

# Step 3: Copy real influenza HA protein sequences from bundled assets
# 12 real HA protein sequences from NCBI Protein database
# Source accessions: AAD17229.1/ABD77675.1 (H1N1 1918), ACP41105.1 (H1N1 2009),
#   ABQ44486.1 (H3N2 1968), AAT73274.1 (H5N1 2004), AGJ51966.1 (H7N9 2013),
#   AAA43178.1 (H2N2 1957), plus seasonal and recent strains
# Subtypes: H1N1, H2N2, H3N2, H5N1, H7N9, H9N2 spanning 1918-2023
cp /workspace/assets/influenza_HA_strains.fasta /home/ga/UGENE_Data/vaccine/influenza_HA_strains.fasta

chown -R ga:ga /home/ga/UGENE_Data/vaccine

# Step 4: RECORD
date +%s > /tmp/vaccine_epitope_conservation_start_ts
ls /home/ga/UGENE_Data/vaccine/results/ 2>/dev/null > /tmp/vaccine_epitope_conservation_setup_files.txt

# Ground truth
python3 << 'PYEOF'
import json
gt = {
    "total_sequences": 12,
    "subtypes": ["H1N1", "H3N2", "H5N1", "H7N9", "H9N2", "H2N2"],
    "min_epitope_length": 9,
    "expected_conserved_motifs": ["CYPYDVPDY", "KLYIWG", "ASGRITV", "STKRSQQ"]
}
with open("/tmp/vaccine_epitope_conservation_gt.json", "w") as f:
    json.dump(gt, f)
PYEOF

# Step 5: Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

TIMEOUT=90
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
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
    ELAPSED=0
    while [ $ELAPSED -lt 60 ]; do
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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    DISPLAY=:1 scrot /tmp/vaccine_epitope_conservation_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
