#!/bin/bash
echo "=== Exporting PCR Validation Task Results ==="

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gather file data into a robust JSON using Python
python3 << 'PYEOF'
import json
import os

RESULTS_DIR = "/home/ga/UGENE_Data/pcr_results"
GT_FILE = "/var/lib/pcr_ground_truth/expected.json"
START_TIME_FILE = "/tmp/task_start_time.txt"

def read_file(path, max_bytes=50000):
    if not os.path.exists(path):
        return None
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read(max_bytes)
    except Exception as e:
        return str(e)

def get_mtime(path):
    try:
        return os.path.getmtime(path)
    except:
        return 0

try:
    with open(START_TIME_FILE, 'r') as f:
        start_time = float(f.read().strip())
except:
    start_time = 0.0

gt_data = {}
try:
    with open(GT_FILE, 'r') as f:
        gt_data = json.load(f)
except:
    pass

# Search for the expected output files (accommodating slight naming variations)
def find_file(names):
    for name in names:
        path = os.path.join(RESULTS_DIR, name)
        if os.path.exists(path):
            return path
    return os.path.join(RESULTS_DIR, names[0])

fasta_path = find_file(["amplicon.fasta", "amplicon.fa", "amplicon.fna"])
gb_path = find_file(["insulin_pcr_annotated.gb", "insulin_annotated.gb", "annotated.gb", "insulin.gb"])
report_path = find_file(["pcr_validation_report.txt", "validation_report.txt", "report.txt"])

export_data = {
    "task_start_time": start_time,
    "ground_truth": gt_data,
    "files": {
        "amplicon_fasta": {
            "exists": os.path.exists(fasta_path),
            "mtime": get_mtime(fasta_path),
            "content": read_file(fasta_path)
        },
        "annotated_gb": {
            "exists": os.path.exists(gb_path),
            "mtime": get_mtime(gb_path),
            "content": read_file(gb_path)
        },
        "report": {
            "exists": os.path.exists(report_path),
            "mtime": get_mtime(report_path),
            "content": read_file(report_path)
        }
    }
}

# Write out for verifier
with open('/tmp/pcr_result.json', 'w') as f:
    json.dump(export_data, f)
PYEOF

# Ensure permissions allow copy_from_env
chmod 666 /tmp/pcr_result.json 2>/dev/null || true

echo "Export complete. Result packaged to /tmp/pcr_result.json"