#!/bin/bash
echo "=== Setting up agricultural_pathogen_classification task ==="

# Step 1: CLEAN
rm -rf /home/ga/UGENE_Data/agriculture/results 2>/dev/null || true
rm -f /tmp/agricultural_pathogen_classification_* 2>/dev/null || true

# Step 2: Create directories
mkdir -p /home/ga/UGENE_Data/agriculture/results
mkdir -p /home/ga/UGENE_Data/agriculture

# Step 3: Copy real ITS sequences from bundled assets
# Reference sequences: Real ITS sequences from NCBI GenBank for 10 wheat fungal pathogens
# Source accessions: PZ014411.1 (F. graminearum), PV098983.1 (P. triticina),
#   PV416552.1 (B. graminis), MH862992.1 (Z. tritici), OQ257148.1 (P. tritici-repentis),
#   MH855829.1 (T. caries), PV827756.1 (U. tritici), PV849335.1 (R. cerealis),
#   MH855056.1 (G. tritici), PZ027992.1 (B. sorokiniana)
cp /workspace/assets/reference_wheat_pathogens_ITS.fasta /home/ga/UGENE_Data/agriculture/reference_wheat_pathogens_ITS.fasta

# Unknown pathogen: Modified F. graminearum ITS with 3 SNPs (error-injection scaffolding)
cp /workspace/assets/unknown_pathogen_ITS.fasta /home/ga/UGENE_Data/agriculture/unknown_pathogen_ITS.fasta

chown -R ga:ga /home/ga/UGENE_Data/agriculture

# Step 4: RECORD
date +%s > /tmp/agricultural_pathogen_classification_start_ts
ls /home/ga/UGENE_Data/agriculture/results/ 2>/dev/null > /tmp/agricultural_pathogen_classification_setup_files.txt

# Step 5: Ground truth
python3 << 'PYEOF'
import json
gt = {
    "unknown_identity": "Fusarium_graminearum",
    "total_sequences": 11,
    "reference_count": 10,
    "expected_closest_neighbor": "Fusarium_graminearum",
    "pathogen_names": [
        "Fusarium_graminearum", "Puccinia_triticina", "Blumeria_graminis",
        "Zymoseptoria_tritici", "Pyrenophora_tritici_repentis", "Tilletia_caries",
        "Ustilago_tritici", "Rhizoctonia_cerealis", "Gaeumannomyces_tritici",
        "Bipolaris_sorokiniana"
    ]
}
with open("/tmp/agricultural_pathogen_classification_gt.json", "w") as f:
    json.dump(gt, f)
PYEOF

# Step 6: Launch UGENE
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
    DISPLAY=:1 scrot /tmp/agricultural_pathogen_classification_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
