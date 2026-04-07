#!/bin/bash
echo "=== Exporting plasmid_standardization_orf_mapping results ==="

RESULTS_DIR="/home/ga/UGENE_Data/plasmid/results"
TASK_START=$(cat /tmp/plasmid_task_start_ts 2>/dev/null || echo "0")

# Take end screenshot
DISPLAY=:1 scrot /tmp/plasmid_task_end_screenshot.png 2>/dev/null || true

# Extract data using Python and export to JSON
cat << 'PYEOF' > /tmp/export_plasmid_data.py
import json
import os

results_dir = "/home/ga/UGENE_Data/plasmid/results"
fasta_path = os.path.join(results_dir, "standardized_plasmid.fasta")
report_path = os.path.join(results_dir, "standardization_report.txt")

result = {
    "fasta_exists": False,
    "fasta_seq": "",
    "fasta_created_during_task": False,
    "report_exists": False,
    "report_content": ""
}

task_start = int(open("/tmp/plasmid_task_start_ts").read().strip()) if os.path.exists("/tmp/plasmid_task_start_ts") else 0

if os.path.exists(fasta_path):
    result["fasta_exists"] = True
    mtime = os.path.getmtime(fasta_path)
    if mtime > task_start:
        result["fasta_created_during_task"] = True
        
    with open(fasta_path, 'r') as f:
        seq = "".join(l.strip() for l in f if not l.startswith(">"))
        result["fasta_seq"] = seq.upper()

if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, 'r') as f:
        result["report_content"] = f.read()

with open("/tmp/plasmid_task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

python3 /tmp/export_plasmid_data.py
chmod 666 /tmp/plasmid_task_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/plasmid_task_result.json"
echo "=== Export complete ==="