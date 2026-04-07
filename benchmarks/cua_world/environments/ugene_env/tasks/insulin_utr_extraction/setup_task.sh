#!/bin/bash
set -e
echo "=== Setting up insulin_utr_extraction task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
rm -f /tmp/utr_ground_truth.json 2>/dev/null || true
rm -f /tmp/insulin_utr_extraction_result.json 2>/dev/null || true

mkdir -p /home/ga/UGENE_Data/results
mkdir -p /home/ga/UGENE_Data

# 2. Ensure the reference file exists (fallback to bundled assets if needed)
if [ ! -f /home/ga/UGENE_Data/human_insulin_gene.gb ]; then
    if [ -f /opt/ugene_data/human_insulin_gene.gb ]; then
        cp /opt/ugene_data/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
    elif [ -f /workspace/assets/human_insulin_gene.gb ]; then
        cp /workspace/assets/human_insulin_gene.gb /home/ga/UGENE_Data/human_insulin_gene.gb
    else
        echo "ERROR: Could not find human_insulin_gene.gb"
        exit 1
    fi
fi
chown -R ga:ga /home/ga/UGENE_Data

# 3. Dynamically extract ground truth via Python to ensure verifier is robust to data updates
python3 << 'PYEOF'
import re, json, os

file_path = "/home/ga/UGENE_Data/human_insulin_gene.gb"
with open(file_path, "r") as f:
    data = f.read()

# Parse CDS coordinates
cds_match = re.search(r'CDS\s+(\d+)\.\.(\d+)', data)
if cds_match:
    cds_start = int(cds_match.group(1))
    cds_end = int(cds_match.group(2))
else:
    # Fallback to known NM_000207.3 coordinates if regex fails
    cds_start, cds_end = 60, 392

# Parse ORIGIN sequence
origin_match = re.search(r'ORIGIN\s*(.*?)\/\/', data, re.DOTALL)
if origin_match:
    raw_seq = origin_match.group(1)
    seq = re.sub(r'[\d\s\n]', '', raw_seq).upper()
else:
    seq = ""

# GenBank uses 1-based inclusive indexing
# 5' UTR: index 0 to cds_start - 2 (inclusive)
# 3' UTR: index cds_end to end of string
utr5 = seq[:cds_start - 1]
utr3 = seq[cds_end:]

def gc_content(s):
    if not s: return 0.0
    return (s.count('G') + s.count('C')) / len(s) * 100.0

gt = {
    "cds_start": cds_start,
    "cds_end": cds_end,
    "utr5_seq": utr5,
    "utr5_len": len(utr5),
    "utr5_gc": round(gc_content(utr5), 2),
    "utr3_seq": utr3,
    "utr3_len": len(utr3),
    "utr3_gc": round(gc_content(utr3), 2)
}

with open("/tmp/utr_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

chmod 644 /tmp/utr_ground_truth.json

# 4. Record timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window
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
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="