#!/bin/bash
echo "=== Exporting lambda_ladder_double_digest results ==="

# Record end state
DISPLAY=:1 scrot /tmp/lambda_task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/lambda_task_start_ts 2>/dev/null || echo "0")

# Prepare a Python script to parse the files and output JSON
cat > /tmp/parse_lambda_results.py << 'PYEOF'
import json
import os
import re

task_start = int(os.environ.get('TASK_START', 0))
results_dir = "/home/ga/UGENE_Data/lambda_phage/results"
fasta_file = os.path.join(results_dir, "ladder_fragments.fasta")
txt_file = os.path.join(results_dir, "ladder_sizes.txt")

fasta_exists = os.path.isfile(fasta_file)
txt_exists = os.path.isfile(txt_file)

fasta_created_during_task = False
if fasta_exists:
    mtime = os.path.getmtime(fasta_file)
    if mtime > task_start:
        fasta_created_during_task = True

txt_created_during_task = False
if txt_exists:
    mtime = os.path.getmtime(txt_file)
    if mtime > task_start:
        txt_created_during_task = True

# Parse FASTA
fragment_lengths = []
if fasta_exists:
    with open(fasta_file, 'r', encoding='utf-8', errors='ignore') as f:
        seq = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq:
                    fragment_lengths.append(len(seq))
                    seq = ""
            else:
                # Remove spaces or gaps if any exist
                seq += re.sub(r'[^A-Za-z]', '', line)
        if seq:
            fragment_lengths.append(len(seq))

# Parse TXT
reported_sizes = []
txt_content = ""
if txt_exists:
    with open(txt_file, 'r', encoding='utf-8', errors='ignore') as f:
        txt_content = f.read()
        # Find all numbers in the file
        matches = re.findall(r'\b\d+\b', txt_content)
        reported_sizes = [int(m) for m in matches]

result = {
    "task_start_time": task_start,
    "fasta_exists": fasta_exists,
    "fasta_created_during_task": fasta_created_during_task,
    "txt_exists": txt_exists,
    "txt_created_during_task": txt_created_during_task,
    "extracted_lengths": sorted(fragment_lengths, reverse=True),
    "fasta_sequence_count": len(fragment_lengths),
    "reported_sizes": reported_sizes,
    "raw_txt_content": txt_content[:500]
}

with open("/tmp/lambda_digest_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Run parsing script
export TASK_START
python3 /tmp/parse_lambda_results.py

# Ensure permissions are correct for verifier to read
chmod 666 /tmp/lambda_digest_result.json 2>/dev/null || true

echo "Export completed. Results summary:"
cat /tmp/lambda_digest_result.json