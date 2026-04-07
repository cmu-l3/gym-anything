#!/bin/bash
set -e
echo "=== Setting up plasmid_standardization_orf_mapping task ==="

# Clean stale artifacts
rm -rf /home/ga/UGENE_Data/plasmid/results 2>/dev/null || true
rm -f /tmp/plasmid_task_* 2>/dev/null || true
rm -f /tmp/plasmid_gt.json 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/UGENE_Data/plasmid/results

# Generate the synthetic deterministic plasmid sequence and ground truth
# This python script creates a mathematically perfect plasmid sequence, rotates it,
# and dynamically computes the ground truth for the verifier.
cat << 'PYEOF' > /tmp/generate_plasmid.py
import json
import random

# 1. Generate deterministic sequence backbone
random.seed(123)
bases = ['A', 'C', 'G', 'T']
seq_list = [random.choice(bases) for _ in range(2686)]
seq = "".join(seq_list)

# Remove accidental motifs to ensure uniqueness
seq = seq.replace("GAATTC", "GAAATC")
seq = seq.replace("ATG", "ATC")

# 2. Insert exactly one EcoRI site at index 395
seq = seq[:395] + "GAATTC" + seq[401:]

# 3. Create a synthetic AmpR ORF (Reverse Complement)
# Direct ORF: ATG (start) + MSIQHFRVAL + 289*Lys + TAA (stop) = 903 bp
direct_orf = "ATG" + "TCCATCCAACACTTCCGCGTCGCTTTA" + "AAA" * 289 + "TAA"
comp = {'A':'T', 'C':'G', 'G':'C', 'T':'A'}
rev_comp_orf = "".join(comp[b] for b in reversed(direct_orf))

# Insert ORF into backbone at index 1600
seq = seq[:1600] + rev_comp_orf + seq[1600+len(rev_comp_orf):]

# 4. Rotate by arbitrary offset to simulate assembler output
offset = 850
raw_seq = seq[offset:] + seq[:offset]

# 5. Save the raw sequence for the agent
with open('/home/ga/UGENE_Data/plasmid/raw_psynbio.fasta', 'w') as f:
    f.write(">raw_psynbio_synthetic_plasmid\n")
    for i in range(0, len(raw_seq), 60):
        f.write(raw_seq[i:i+60] + "\n")

# 6. Compute Ground Truth dynamically
original_length = len(seq)
ecori_pos_in_raw = raw_seq.find("GAATTC") + 1

# Standardized sequence (what the agent should generate)
std_seq = raw_seq[ecori_pos_in_raw-1:] + raw_seq[:ecori_pos_in_raw-1]

# Find longest ORF
codon_table = {
    'ATA':'I', 'ATC':'I', 'ATT':'I', 'ATG':'M', 'ACA':'T', 'ACC':'T', 'ACG':'T', 'ACT':'T',
    'AAC':'N', 'AAT':'N', 'AAA':'K', 'AAG':'K', 'AGC':'S', 'AGT':'S', 'AGA':'R', 'AGG':'R',
    'CTA':'L', 'CTC':'L', 'CTG':'L', 'CTT':'L', 'CCA':'P', 'CCC':'P', 'CCG':'P', 'CCT':'P',
    'CAC':'H', 'CAT':'H', 'CAA':'Q', 'CAG':'Q', 'CGA':'R', 'CGC':'R', 'CGG':'R', 'CGT':'R',
    'GTA':'V', 'GTC':'V', 'GTG':'V', 'GTT':'V', 'GCA':'A', 'GCC':'A', 'GCG':'A', 'GCT':'A',
    'GAC':'D', 'GAT':'D', 'GAA':'E', 'GAG':'E', 'GGA':'G', 'GGC':'G', 'GGG':'G', 'GGT':'G',
    'TCA':'S', 'TCC':'S', 'TCG':'S', 'TCT':'S', 'TTC':'F', 'TTT':'F', 'TTA':'L', 'TTG':'L',
    'TAC':'Y', 'TAT':'Y', 'TAA':'_', 'TAG':'_', 'TGC':'C', 'TGT':'C', 'TGA':'_', 'TGG':'W',
}

def reverse_complement(s):
    c = {'A':'T', 'C':'G', 'G':'C', 'T':'A', 'N':'N'}
    return "".join(c.get(b, 'N') for b in reversed(s))

def find_orfs(sequence, strand, is_rev=False):
    orfs = []
    seq_len = len(sequence)
    for frame in range(3):
        for i in range(frame, seq_len - 2, 3):
            if sequence[i:i+3] == 'ATG':
                for j in range(i+3, seq_len - 2, 3):
                    if codon_table.get(sequence[j:j+3], '') == '_':
                        orf_len = j - i + 3
                        if orf_len >= 500:
                            start_pos = i + 1
                            end_pos = j + 3
                            if is_rev:
                                actual_start = seq_len - end_pos + 1
                                actual_end = seq_len - start_pos + 1
                                start_pos, end_pos = actual_start, actual_end
                            
                            prot = "".join(codon_table.get(sequence[k:k+3], 'X') for k in range(i, j, 3))
                            orfs.append({
                                'start': start_pos, 'end': end_pos,
                                'length': orf_len, 'strand': strand, 'protein': prot
                            })
                        break
    return orfs

all_orfs = find_orfs(std_seq, 'Direct') + find_orfs(reverse_complement(std_seq), 'Complement', True)
longest_orf = max(all_orfs, key=lambda x: x['length'])

gt = {
    "original_length": original_length,
    "ecori_pos": ecori_pos_in_raw,
    "std_seq": std_seq,
    "orf_start": longest_orf['start'],
    "orf_end": longest_orf['end'],
    "orf_strand": longest_orf['strand'],
    "orf_first_10_aa": longest_orf['protein'][:10]
}

with open('/tmp/plasmid_gt.json', 'w') as f:
    json.dump(gt, f)
PYEOF

python3 /tmp/generate_plasmid.py
chown -R ga:ga /home/ga/UGENE_Data/plasmid

# Record task start time
date +%s > /tmp/plasmid_task_start_ts

# Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

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
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    # Capture initial screenshot
    DISPLAY=:1 scrot /tmp/plasmid_task_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="