#!/bin/bash
echo "=== Setting up forensic_str_profiling task ==="

# Step 1: CLEAN — remove stale output artifacts
rm -rf /home/ga/UGENE_Data/forensic/results 2>/dev/null || true
rm -f /tmp/forensic_str_profiling_* 2>/dev/null || true

# Step 2: Create directory structure
mkdir -p /home/ga/UGENE_Data/forensic/results
mkdir -p /home/ga/UGENE_Data/forensic

# Step 3: Copy real CODIS STR locus GenBank files from bundled assets
# D13S317 locus — real microsatellite record from NCBI (MH167239, 206bp)
# Contains TATC[16] tandem repeat at positions 67-166
cp /workspace/assets/D13S317_reference.gb /home/ga/UGENE_Data/forensic/D13S317_locus.gb

# TH01 locus — real tyrosine hydroxylase gene from NCBI (D00269, 2838bp)
# Contains TCAT/AATG repeat in intron 1 at positions ~1170-1205
cp /workspace/assets/TH01_D00269.gb /home/ga/UGENE_Data/forensic/TH01_locus.gb

# vWA locus — real von Willebrand factor gene from NCBI (M25858.1, 5285bp)
# Contains TCTA/TCTG repeat in intron 40, annotated repeat_region at 1683-2347
cp /workspace/assets/vWA_M25858.gb /home/ga/UGENE_Data/forensic/vWA_locus.gb

# Create evidence sample alleles (crime scene DNA fragments containing only the repeat region)
cat > /home/ga/UGENE_Data/forensic/evidence_sample_alleles.fasta << 'FASTA'
>Evidence_D13S317_allele1 D13S317 locus evidence allele - 11 TATC repeats
TATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATC
>Evidence_vWA_allele1 vWA locus evidence allele - 16 TCTA repeats
TCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTATCTA
>Evidence_TH01_allele1 TH01 locus evidence allele - 7 TCAT repeats
TCATTCATTCATTCATTCATTCATTCAT
FASTA

chown -R ga:ga /home/ga/UGENE_Data/forensic

# Step 4: RECORD — timestamp after clean, before launch
date +%s > /tmp/forensic_str_profiling_start_ts

# Step 5: Record initial state of results directory
ls /home/ga/UGENE_Data/forensic/results/ 2>/dev/null > /tmp/forensic_str_profiling_setup_files.txt

# Compute ground truth from actual data (real NCBI records)
python3 << 'PYEOF'
import json

# Ground truth derived from real NCBI GenBank records
gt = {
    "D13S317": {
        "repeat_motif": "TATC",
        "alt_motif": "AGAT",
        "expected_repeat_region_start_min": 60,
        "expected_repeat_region_start_max": 80,
        "expected_repeat_region_end_min": 130,
        "expected_repeat_region_end_max": 170,
        "evidence_repeat_count": 11
    },
    "vWA": {
        "repeat_motif": "TCTA",
        "alt_motif": "AGAT",
        "expected_repeat_region_start_min": 1680,
        "expected_repeat_region_start_max": 1750,
        "expected_repeat_region_end_min": 1780,
        "expected_repeat_region_end_max": 2350,
        "evidence_repeat_count": 16
    },
    "TH01": {
        "repeat_motif": "TCAT",
        "alt_motif": "AATG",
        "expected_repeat_region_start_min": 1160,
        "expected_repeat_region_start_max": 1180,
        "expected_repeat_region_end_min": 1195,
        "expected_repeat_region_end_max": 1210,
        "evidence_repeat_count": 7
    }
}
with open("/tmp/forensic_str_profiling_gt.json", "w") as f:
    json.dump(gt, f)
print("Ground truth written")
PYEOF

# Step 6: Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# Step 7: Launch UGENE
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Step 8: Wait for UGENE window
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
    DISPLAY=:1 scrot /tmp/forensic_str_profiling_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
