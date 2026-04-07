#!/bin/bash
echo "=== Setting up insulin_motif_annotation task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results

# 2. Verify input file exists (fallback to download if missing from env setup)
if [ ! -s /home/ga/UGENE_Data/human_insulin_gene.gb ]; then
    echo "WARNING: Input file missing, downloading reference insulin gene..."
    wget -q -O /home/ga/UGENE_Data/human_insulin_gene.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text"
fi
chown ga:ga /home/ga/UGENE_Data/human_insulin_gene.gb

# 3. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

# 4. Generate Programmatic Ground Truth directly from the input sequence
echo "Calculating ground truth motifs..."
python3 << 'PYEOF'
import re, json

try:
    with open("/home/ga/UGENE_Data/human_insulin_gene.gb") as f:
        content = f.read()

    # Extract raw nucleotide sequence
    origin_match = re.search(r'ORIGIN\s+(.*?)\/\/', content, re.DOTALL)
    if origin_match:
        seq = re.sub(r'[\d\s\n]', '', origin_match.group(1)).upper()
    else:
        seq = ""

    # Reverse complement helper
    def rc(s):
        return s.translate(str.maketrans("ACGT", "TGCA"))[::-1]

    seq_rc = rc(seq)

    # Regex definitions for required motifs
    motifs = {
        "TATA_box": r'TATAAA',
        "GC_box": r'GGGCGG',
        "polyA_signal": r'AATAAA',
        "E_box": r'CA[ACGT]{2}TG',
        "CArG_box": r'CC[AT]{6}GG'
    }

    gt = {}
    for name, pattern in motifs.items():
        matches = set()
        # Find forward strand matches
        for m in re.finditer(pattern, seq):
            matches.add((m.start()+1, m.end()))
        # Find reverse strand matches
        for m in re.finditer(pattern, seq_rc):
            start = len(seq) - m.end() + 1
            end = len(seq) - m.start()
            matches.add((start, end))
            
        gt[name] = len(matches)

    with open("/tmp/insulin_motif_gt.json", "w") as f:
        json.dump(gt, f)
    print(f"Generated Ground Truth: {gt}")

except Exception as e:
    print(f"Failed to generate GT: {e}")
PYEOF

# 5. Launch UGENE directly with the input file
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh /home/ga/UGENE_Data/human_insulin_gene.gb >/dev/null 2>&1 &"

# Wait for UGENE window
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 5

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any potential popup tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take setup screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="