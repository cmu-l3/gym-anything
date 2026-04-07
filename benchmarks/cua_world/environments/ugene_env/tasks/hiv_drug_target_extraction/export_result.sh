#!/bin/bash
echo "=== Exporting hiv_drug_target_extraction results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGETS_DIR="/home/ga/UGENE_Data/virology/targets"

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract sequences and write securely to JSON using Python
python3 << PYEOF
import json
import os
import glob
import time

def read_fasta_seq(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'r') as f:
        lines = f.readlines()
    if not lines or not lines[0].startswith('>'):
        return None  # Not a valid FASTA
    # Join everything except the header line
    seq = "".join(line.strip() for line in lines if not line.startswith('>'))
    return seq.upper()

def file_mtime(filepath):
    if not os.path.exists(filepath):
        return 0
    return int(os.path.getmtime(filepath))

targets_dir = "${TARGETS_DIR}"
prot_path = os.path.join(targets_dir, "protease.fasta")
rt_path = os.path.join(targets_dir, "reverse_transcriptase.fasta")
int_path = os.path.join(targets_dir, "integrase.fasta")
report_path = os.path.join(targets_dir, "target_lengths.txt")

# Read sequences
prot_seq = read_fasta_seq(prot_path)
rt_seq = read_fasta_seq(rt_path)
int_seq = read_fasta_seq(int_path)

# Read report
report_content = ""
if os.path.exists(report_path):
    with open(report_path, 'r') as f:
        report_content = f.read()

# Build export object
export_data = {
    "task_start_ts": int("${TASK_START}" or "0"),
    "protease": {
        "exists": os.path.exists(prot_path),
        "mtime": file_mtime(prot_path),
        "sequence": prot_seq
    },
    "reverse_transcriptase": {
        "exists": os.path.exists(rt_path),
        "mtime": file_mtime(rt_path),
        "sequence": rt_seq
    },
    "integrase": {
        "exists": os.path.exists(int_path),
        "mtime": file_mtime(int_path),
        "sequence": int_seq
    },
    "report": {
        "exists": os.path.exists(report_path),
        "content": report_content
    }
}

# Ensure atomic/permission-safe write
tmp_out = "/tmp/hiv_extraction_result_tmp.json"
final_out = "/tmp/hiv_extraction_result.json"

with open(tmp_out, "w") as f:
    json.dump(export_data, f, indent=2)

os.system(f"mv {tmp_out} {final_out}")
os.system(f"chmod 666 {final_out}")
PYEOF

echo "Result JSON written to /tmp/hiv_extraction_result.json"
echo "=== Export complete ==="