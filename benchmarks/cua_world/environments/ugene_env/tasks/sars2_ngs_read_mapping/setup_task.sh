#!/bin/bash
set -e

echo "=== Setting up sars2_ngs_read_mapping task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/ngs 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/ngs/results
chown -R ga:ga /home/ga/UGENE_Data/ngs

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Generate realistic biological data (Reference and Mutated FASTQ)
echo "Generating reference and FASTQ data..."
cat << 'PYEOF' > /tmp/generate_ngs_data.py
import urllib.request
import os

ref_file = "/home/ga/UGENE_Data/ngs/sars2_spike_reference.fasta"
fastq_file = "/home/ga/UGENE_Data/ngs/patient_reads.fastq"

# Attempt to download real SARS-CoV-2 Spike gene (NC_045512.2, pos 21563-25384)
url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_045512.2&seq_start=21563&seq_stop=25384&rettype=fasta"

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=15) as response:
        fasta_data = response.read().decode('utf-8')
    if ">" not in fasta_data:
        raise ValueError("Invalid FASTA response")
    with open(ref_file, "w") as f:
        f.write(fasta_data)
except Exception as e:
    print(f"Download failed ({e}), using fallback sequence.")
    # Fallback: 3822 bases (approx Spike length)
    header = ">NC_045512.2:21563-25384 Severe acute respiratory syndrome coronavirus 2 isolate Wuhan-Hu-1, complete genome\n"
    dummy_seq = ("ATGTTTGTTTTTCTTGTTTTATTGCCACTAGTCTCTAGTCAGTGTGTTAATCTTACAACCAGAACTCAATTACCCCCTGC" * 48) # 3840 bases
    with open(ref_file, "w") as f:
        f.write(header + dummy_seq)

# Read the reference sequence to generate reads
with open(ref_file, 'r') as f:
    lines = f.read().strip().split('\n')

header = lines[0]
seq = ''.join(lines[1:]).upper()
seq = ''.join([c for c in seq if c in 'ACGT'])

# Inject D614G equivalent mutation (A -> G at index 1840 / 1-based pos 1841)
seq_list = list(seq)
if len(seq_list) > 1840:
    seq_list[1840] = 'G'
mut_seq = ''.join(seq_list)

# Generate synthetic FASTQ reads (100bp) with ~8x coverage
read_len = 100
step = 25
with open(fastq_file, "w") as out:
    # Forward reads
    for i in range(0, len(mut_seq) - read_len + 1, step):
        read = mut_seq[i:i+read_len]
        out.write(f"@READ_FWD_{i}\n{read}\n+\n{'I'*read_len}\n")
    
    # Reverse complement reads
    trans = str.maketrans('ACGT', 'TGCA')
    for i in range(12, len(mut_seq) - read_len + 1, step):
        read = mut_seq[i:i+read_len]
        rev_comp = read.translate(trans)[::-1]
        out.write(f"@READ_REV_{i}\n{rev_comp}\n+\n{'I'*read_len}\n")

print("Data generation complete.")
PYEOF

python3 /tmp/generate_ngs_data.py
chown -R ga:ga /home/ga/UGENE_Data/ngs

# 4. Kill existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# 5. Launch UGENE and setup UI state
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

sleep 4

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize UGENE
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="