#!/bin/bash
echo "=== Exporting rabies_proteome_extraction results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract results using Python for robustness
python3 << 'PYEOF'
import json
import os
import glob
import re

RESULTS_DIR = "/home/ga/UGENE_Data/results"

# Find exported FASTA file
fasta_files = glob.glob(os.path.join(RESULTS_DIR, "*.fasta")) + glob.glob(os.path.join(RESULTS_DIR, "*.fa"))
fasta_exists = len(fasta_files) > 0

seq_count = 0
max_len = 0
total_len = 0

if fasta_exists:
    with open(fasta_files[0], 'r') as f:
        lines = f.readlines()
        
    seqs = []
    curr_seq = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if curr_seq:
                seqs.append("".join(curr_seq))
            curr_seq = []
        else:
            # Strip spaces, asterisks (stop codons) to accurately measure sequence
            clean_line = re.sub(r'[\s\*]', '', line)
            curr_seq.append(clean_line)
            
    if curr_seq:
        seqs.append("".join(curr_seq))
        
    seq_count = len(seqs)
    if seq_count > 0:
        lengths = [len(s) for s in seqs]
        max_len = max(lengths)
        total_len = sum(lengths)

# Find the summary report
report_files = glob.glob(os.path.join(RESULTS_DIR, "*.txt"))
report_exists = len(report_files) > 0
report_content = ""

if report_exists:
    with open(report_files[0], 'r') as f:
        # Read the first 2000 chars to prevent massive output issues
        report_content = f.read(2000)

result_data = {
    "fasta_exists": fasta_exists,
    "seq_count": seq_count,
    "max_len": max_len,
    "total_len": total_len,
    "report_exists": report_exists,
    "report_content": report_content
}

# Ensure atomic write and wide permissions
with open("/tmp/task_result_temp.json", "w") as f:
    json.dump(result_data, f, indent=4)

PYEOF

mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported successfully to /tmp/task_result.json"
cat /tmp/task_result.json