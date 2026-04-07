#!/bin/bash
echo "=== Setting up In Silico PCR Validation Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/UGENE_Data/pcr_results
chown -R ga:ga /home/ga/UGENE_Data/pcr_results

# Ensure the insulin GenBank file exists
INSULIN_GB="/home/ga/UGENE_Data/human_insulin_gene.gb"
if [ ! -s "$INSULIN_GB" ]; then
    echo "ERROR: Insulin GenBank file not found at $INSULIN_GB. Downloading fallback..."
    wget --timeout=60 -q \
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_000207.3&rettype=gb&retmode=text" \
        -O "$INSULIN_GB" || true
fi

# Use Python to dynamically generate a guaranteed-matching primer pair and ground truth
python3 << 'PYEOF'
import re
import json
import os

gb_file = "/home/ga/UGENE_Data/human_insulin_gene.gb"

# Parse GenBank ORIGIN
with open(gb_file, 'r') as f:
    gb_text = f.read()

origin_match = re.search(r'ORIGIN\s+(.*?)\/\/', gb_text, re.DOTALL)
if not origin_match:
    print("Failed to parse GenBank origin.")
    exit(1)

# Clean sequence (remove numbers and spaces)
full_seq = re.sub(r'[^a-zA-Z]', '', origin_match.group(1)).upper()
seq_len = len(full_seq)

# Design primers (Forward at ~15%, Reverse at ~45%)
fwd_start = max(10, int(seq_len * 0.15))
fwd_primer = full_seq[fwd_start:fwd_start + 20]

rev_end = min(seq_len - 10, int(seq_len * 0.45))
rev_region = full_seq[rev_end - 20:rev_end]

# Reverse complement for the reverse primer
complement = {'A': 'T', 'T': 'A', 'G': 'C', 'C': 'G', 'N': 'N'}
rev_primer = ''.join(complement.get(b, 'N') for b in reversed(rev_region))

amplicon_size = rev_end - fwd_start
amplicon_seq = full_seq[fwd_start:rev_end]

# Write primer file for the agent
primer_path = "/home/ga/UGENE_Data/pcr_primers.txt"
with open(primer_path, 'w') as f:
    f.write("# PCR Primer Pair for Human Insulin Gene Diagnostic Assay\n")
    f.write("# Target: Human insulin mRNA\n#\n")
    f.write(f"Forward Primer (5'->3'): {fwd_primer}\n")
    f.write(f"Reverse Primer (5'->3'): {rev_primer}\n")
    f.write(f"#\n# Expected size: ~{amplicon_size} bp\n")

# Write ground truth for the verifier (hidden from agent)
os.makedirs("/var/lib/pcr_ground_truth", exist_ok=True)
gt = {
    "fwd_primer": fwd_primer,
    "rev_primer": rev_primer,
    "fwd_start": fwd_start + 1,
    "rev_end": rev_end,
    "amplicon_size": amplicon_size,
    "amplicon_seq": amplicon_seq,
    "full_seq": full_seq
}
with open("/var/lib/pcr_ground_truth/expected.json", 'w') as f:
    json.dump(gt, f)
os.chmod("/var/lib/pcr_ground_truth", 0o700)
PYEOF

chown ga:ga /home/ga/UGENE_Data/pcr_primers.txt
chmod 644 /home/ga/UGENE_Data/pcr_primers.txt

# Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE directly with the GenBank file loaded
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority LD_LIBRARY_PATH=/opt/ugene:\$LD_LIBRARY_PATH /opt/ugene/ugeneui '$INSULIN_GB' > /tmp/ugene_task.log 2>&1 &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected"
        break
    fi
    sleep 2
done

# Give UI time to stabilize
sleep 5

# Maximize the window and dismiss dialogs
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="