#!/bin/bash
echo "=== Setting up microrna_structure_folding task ==="

# Clean and create directories
rm -rf /home/ga/UGENE_Data/rna 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/rna/results

# Create the FASTA file with 3 real pre-miRNA sequences
# Lengths: hsa-let-7a-1 (80), hsa-mir-155 (64), hsa-mir-21 (72)
cat > /home/ga/UGENE_Data/rna/human_pre_miRNAs.fasta << 'EOF'
>hsa-let-7a-1
UGGGAUGAGGUAGUAGGUUGUAUAGUUUUAGGGUCACACCCACCACUGGGAGAUAACUAUACAAUCUACUGUCUUUCCUA
>hsa-mir-155
CUGUUAAUGCUAAUCGUGAUAGGGGUUUUGCCUCCAACUGACUCCUACAUAUUAGCAUUAACAG
>hsa-mir-21
UGUCGGGUAGCUUAUCAGACUGAUGUUGACUGUUGAAUCUCAUGGCAACACCAGUCGAUGGGCUGUCUGACA
EOF

chown -R ga:ga /home/ga/UGENE_Data/rna

# Record start time
date +%s > /tmp/microrna_task_start_ts

# Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="