#!/bin/bash
set -e

echo "=== Setting up contaminated alignment QC task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/qc_task_start_time.txt

# Create working directories
mkdir -p /home/ga/UGENE_Data/qc_analysis/results
chown -R ga:ga /home/ga/UGENE_Data/qc_analysis

# Build the mixed FASTA file using Python
python3 << 'PYEOF'
import random
import os

def parse_fasta(filepath):
    sequences = []
    current_header = None
    current_seq = []
    if not os.path.exists(filepath):
        return []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if current_header:
                    sequences.append((current_header, "".join(current_seq)))
                current_header = line
                current_seq = []
            elif line:
                current_seq.append(line)
    if current_header:
        sequences.append((current_header, "".join(current_seq)))
    return sequences

def extract_accession(header):
    # UniProt headers: >sp|P68871|HBB_HUMAN ...
    parts = header.split("|")
    if len(parts) >= 2:
        return parts[1]
    return header.split()[0].lstrip(">")

# Load hemoglobin sequences
hbb_seqs = parse_fasta("/home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta")
if not hbb_seqs:
    # Fallback to bundled assets if user space data is missing
    hbb_seqs = parse_fasta("/workspace/assets/hemoglobin_beta_multispecies.fasta")

# Load cytochrome c sequences - look for P99999 (Human Cytochrome c)
cyt_seqs = parse_fasta("/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta")
if not cyt_seqs:
    cyt_seqs = parse_fasta("/workspace/assets/cytochrome_c_multispecies.fasta")

contaminant = None
for header, seq in cyt_seqs:
    acc = extract_accession(header)
    if acc == "P99999":
        contaminant = (acc, seq)
        break

if not contaminant and cyt_seqs:
    contaminant = (extract_accession(cyt_seqs[0][0]), cyt_seqs[0][1])

if not hbb_seqs or not contaminant:
    print("ERROR: Required sequences not found.")
    exit(1)

# Combine: 8 hemoglobin + 1 cytochrome c
all_seqs = []
for header, seq in hbb_seqs[:8]:
    acc = extract_accession(header)
    all_seqs.append((acc, seq))

all_seqs.append(contaminant)

# Shuffle to randomize position
random.seed(42)
random.shuffle(all_seqs)

# Write output with accession-only headers
output_path = "/home/ga/UGENE_Data/qc_analysis/mixed_protein_sequences.fasta"
with open(output_path, "w") as f:
    for acc, seq in all_seqs:
        f.write(f">{acc}\n")
        # Wrap sequence at 70 characters
        for i in range(0, len(seq), 70):
            f.write(seq[i:i+70] + "\n")

print(f"Created mixed FASTA with {len(all_seqs)} sequences at {output_path}")
PYEOF

# Ensure correct ownership
chown -R ga:ga /home/ga/UGENE_Data/qc_analysis

# Close any running UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 2

# Launch UGENE as the user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

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

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="