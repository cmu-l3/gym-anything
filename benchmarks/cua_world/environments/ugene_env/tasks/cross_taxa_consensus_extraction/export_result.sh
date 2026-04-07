#!/bin/bash
echo "=== Exporting cross_taxa_consensus_extraction results ==="

TASK_START=$(cat /tmp/cross_taxa_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/evolution/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to safely read and extract the data to JSON
python3 << EOF
import os
import json
import re

result = {
    "task_start_ts": $TASK_START,
    "fasta_exists": False,
    "fasta_mtime": 0,
    "fasta_content": "",
    "fasta_seq": "",
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "ugene_was_running": False
}

fasta_path = "${RESULTS_DIR}/strict_consensus.fasta"
report_path = "${RESULTS_DIR}/conservation_report.txt"

# Check FASTA file
if os.path.exists(fasta_path):
    result["fasta_exists"] = True
    result["fasta_mtime"] = os.path.getmtime(fasta_path)
    with open(fasta_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        result["fasta_content"] = content[:1000] # Limit size
        # Extract just the sequence (ignore > headers)
        lines = content.split('\n')
        seq = "".join([line.strip() for line in lines if not line.startswith('>')])
        result["fasta_seq"] = seq

# Check Report file
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = os.path.getmtime(report_path)
    with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
        result["report_content"] = f.read()[:2000] # Limit size

# Check if UGENE was running (as a sanity check)
import subprocess
try:
    pgrep_output = subprocess.check_output(['pgrep', '-f', 'ugene']).decode('utf-8')
    if pgrep_output.strip():
        result["ugene_was_running"] = True
except:
    pass

# Write result to temp file
temp_json = "/tmp/cross_taxa_result.json"
with open(temp_json, "w") as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/cross_taxa_result.json 2>/dev/null || sudo chmod 666 /tmp/cross_taxa_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/cross_taxa_result.json"
echo "=== Export complete ==="