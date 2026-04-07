#!/bin/bash
echo "=== Setting up dmd_crispr_sgrna_discovery task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/crispr 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/crispr/results

# 2. Generate the real-world sequence (Human DMD Exon 51 + flanking introns) and calculate ground truth
# Using Python to ensure the Ground Truth perfectly matches the generated FASTA
python3 << 'PYEOF'
import json
import os

# Realistic segment of DMD gene containing Exon 51 and intronic flanks
seq = (
    "TAAATATAAATATATTTACATCACATACAATATTTAAAATCATCTCAGAATTTCTTTATATCCTAGATT"
    "CAGCTTCTCCTGCCAAATCCTGAAAAGCACCAACACAAAATGCCACTTATCCTGCCTTTTAGTTCCTTA"
    "CCTAAAAGTTTAAAAACAAACTTAAATTGTATCTTTTTTCATCTACCATGTGTCCAAAGCTAAGAAACC"
    "AAATGCTGCCTGTTAAGGATAAAATGCTGCATTTAATGCTTCCTCTTTACTAAAGTATTCTCTTTTGCC"
    "AAAAGAGCCTCTATCCATTGCAACTTTACATTGTTCAAAAAGAACACTGGACCATGATTGGAACAGTCA"
    "TTCTTGGTAACTCAATTGCTGATGGACCATTTTGCCTGCATGATTTTAAACCATTTAAACACACCTCAA"
    "TTCATAACATGCAATTGGTAGAAGCAACACTATTGCAACCTCAAAACTGGACACACACTTTACTTCATT"
    "CTTTAAATAGGACTACCTCTATAAGTGAGTTGGAGCAAGATCTTACAGGTGGGCACCTTGAGGGTATCC"
    "TGTTTTACATTCTTTTATGC"
)

fasta_path = "/home/ga/UGENE_Data/crispr/dmd_exon51_region.fasta"
with open(fasta_path, "w") as f:
    f.write(">Homo_sapiens_DMD_exon_51_and_flanks\n")
    # Wrap to 70 chars
    for i in range(0, len(seq), 70):
        f.write(seq[i:i+70] + "\n")

# Calculate Ground Truth deterministic counts
# SpCas9 site is 23bp: 20bp guide + NGG (forward) or CCN + 20bp guide (reverse)
target_len = 23
fwd_targets = 0
rev_targets = 0

for i in range(len(seq) - target_len + 1):
    window = seq[i:i+target_len]
    if window.endswith("GG"):
        fwd_targets += 1
    if window.startswith("CC"):
        rev_targets += 1

gt = {
    "total_targets": fwd_targets + rev_targets,
    "fwd_targets": fwd_targets,
    "rev_targets": rev_targets,
    "sequence_length": len(seq),
    "target_length": 23
}

with open("/tmp/dmd_crispr_gt.json", "w") as f:
    json.dump(gt, f)

print(f"Generated FASTA: {len(seq)} bp")
print(f"Ground truth computed: {gt['total_targets']} total targets ({fwd_targets} fwd, {rev_targets} rev)")
PYEOF

chown -R ga:ga /home/ga/UGENE_Data/crispr

# 3. Record task start time
date +%s > /tmp/dmd_crispr_task_start_time

# 4. Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
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
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    
    # Maximize and focus
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 1
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window did not appear."
fi

echo "=== Task setup complete ==="