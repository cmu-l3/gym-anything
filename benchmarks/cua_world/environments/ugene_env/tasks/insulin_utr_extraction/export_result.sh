#!/bin/bash
set -e
echo "=== Exporting insulin_utr_extraction results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check if UGENE was running
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# 4. Use Python to cleanly extract sequences and report content
python3 << 'PYEOF'
import json, os

RESULTS_DIR = "/home/ga/UGENE_Data/results"

def get_fasta_sequence(filename):
    filepath = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(filepath):
        # Allow case-insensitive fallback extensions
        alt_names = [f for f in os.listdir(RESULTS_DIR) if f.lower() == filename.lower() or f.lower() == filename.replace('.fasta', '.fa').lower()]
        if not alt_names:
            return None
        filepath = os.path.join(RESULTS_DIR, alt_names[0])
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        # Remove FASTA headers and strip whitespace/newlines
        seq = "".join([l.strip().upper() for l in lines if not l.startswith(">")])
        return seq
    except Exception:
        return None

utr5_seq = get_fasta_sequence("5_utr.fasta")
utr3_seq = get_fasta_sequence("3_utr.fasta")

report_path = os.path.join(RESULTS_DIR, "utr_analysis_report.txt")
report_content = ""
if os.path.exists(report_path):
    try:
        with open(report_path, 'r') as f:
            report_content = f.read()
    except Exception:
        pass

result = {
    "utr5_exists": utr5_seq is not None,
    "utr5_seq": utr5_seq if utr5_seq is not None else "",
    "utr3_exists": utr3_seq is not None,
    "utr3_seq": utr3_seq if utr3_seq is not None else "",
    "report_exists": os.path.exists(report_path),
    "report_content": report_content
}

with open("/tmp/insulin_utr_extraction_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 644 /tmp/insulin_utr_extraction_result.json

echo "=== Result Export Complete ==="