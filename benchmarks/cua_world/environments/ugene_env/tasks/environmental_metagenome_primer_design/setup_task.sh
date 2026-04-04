#!/bin/bash
echo "=== Setting up environmental_metagenome_primer_design task ==="

# Step 1: CLEAN
rm -rf /home/ga/UGENE_Data/environmental/results 2>/dev/null || true
rm -f /tmp/environmental_metagenome_primer_design_* 2>/dev/null || true

# Step 2: Create directories
mkdir -p /home/ga/UGENE_Data/environmental/results
mkdir -p /home/ga/UGENE_Data/environmental

# Step 3: Copy real 16S rRNA sequences from bundled assets
# SRB sequences: Real 16S rRNA partial sequences from NCBI for 8 sulfate-reducing bacteria
# Source accessions: PV992576.1 (D. vulgaris), PV110867.1 (D. desulfuricans),
#   NR_117122.1 (D. giganteus), PX448252.1 (Db. propionicus),
#   NR_122091.1 (D. africanus), PP977854.1 (D. piger),
#   PX240737.1 (Dm. baculatum), PP882851.1 (Db. postgatei)
cp /workspace/assets/srb_16S_sequences.fasta /home/ga/UGENE_Data/environmental/srb_16S_sequences.fasta

# Non-target sequences: Real 16S rRNA partial sequences from NCBI for 6 common soil bacteria
# Source accessions: PV810134.1 (E. coli), PZ050675.1 (B. subtilis),
#   PZ049890.1 (P. aeruginosa), PZ050804.1 (S. aureus),
#   PZ028441.1 (S. coelicolor), PZ049452.1 (C. butyricum)
cp /workspace/assets/nontarget_16S_sequences.fasta /home/ga/UGENE_Data/environmental/nontarget_16S_sequences.fasta

# Combined file
cat /home/ga/UGENE_Data/environmental/srb_16S_sequences.fasta \
    /home/ga/UGENE_Data/environmental/nontarget_16S_sequences.fasta \
    > /home/ga/UGENE_Data/environmental/all_16S_combined.fasta

chown -R ga:ga /home/ga/UGENE_Data/environmental

# Step 4: RECORD
date +%s > /tmp/environmental_metagenome_primer_design_start_ts
ls /home/ga/UGENE_Data/environmental/results/ 2>/dev/null > /tmp/environmental_metagenome_primer_design_setup_files.txt

# Ground truth
python3 << 'PYEOF'
import json
gt = {
    "total_sequences": 14,
    "srb_count": 8,
    "nontarget_count": 6,
    "target_genera": ["Desulfovibrio", "Desulfobulbus", "Desulfomicrobium", "Desulfobacter"],
    "valid_primer_length_min": 18,
    "valid_primer_length_max": 25,
    "valid_tm_min": 50.0,
    "valid_tm_max": 70.0,
    "valid_amplicon_min": 100,
    "valid_amplicon_max": 600
}
with open("/tmp/environmental_metagenome_primer_design_gt.json", "w") as f:
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
    DISPLAY=:1 scrot /tmp/environmental_metagenome_primer_design_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
