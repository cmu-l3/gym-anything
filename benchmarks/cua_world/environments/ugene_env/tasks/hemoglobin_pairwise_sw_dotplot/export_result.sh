#!/bin/bash
echo "=== Exporting hemoglobin_pairwise_sw_dotplot results ==="

# Take end screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Python script to safely encode contents and avoid shell string escaping issues
python3 << 'PYEOF'
import json, os, base64

def get_file_b64(path):
    if os.path.isfile(path):
        with open(path, "rb") as f:
            # Read up to 100KB to prevent memory issues with massive unintended files
            return base64.b64encode(f.read(102400)).decode("ascii") 
    return ""

results_dir = "/home/ga/UGENE_Data/results"
task_start_file = "/tmp/task_start_time.txt"

task_start = 0
if os.path.isfile(task_start_file):
    try:
        with open(task_start_file, "r") as f:
            task_start = int(f.read().strip())
    except Exception:
        pass

human_fasta = os.path.join(results_dir, "human_hbb.fasta")
chicken_fasta = os.path.join(results_dir, "chicken_hbb.fasta")
aln_file = os.path.join(results_dir, "sw_alignment.aln")
dotplot_file = os.path.join(results_dir, "dotplot.png")
report_file = os.path.join(results_dir, "comparison_report.txt")

result = {
    "task_start_ts": task_start,
    "human_fasta_exists": os.path.isfile(human_fasta) and os.path.getsize(human_fasta) > 0,
    "human_fasta_content_b64": get_file_b64(human_fasta),
    "chicken_fasta_exists": os.path.isfile(chicken_fasta) and os.path.getsize(chicken_fasta) > 0,
    "chicken_fasta_content_b64": get_file_b64(chicken_fasta),
    "aln_exists": os.path.isfile(aln_file) and os.path.getsize(aln_file) > 0,
    "aln_content_b64": get_file_b64(aln_file),
    "dotplot_exists": os.path.isfile(dotplot_file),
    "dotplot_size_bytes": os.path.getsize(dotplot_file) if os.path.isfile(dotplot_file) else 0,
    "report_exists": os.path.isfile(report_file) and os.path.getsize(report_file) > 0,
    "report_content_b64": get_file_b64(report_file)
}

import sys
# Write path is provided via argv in a real script, but we hardcoded TEMP_JSON via bash variable export.
# Let's read from env
temp_json_path = os.environ.get('TEMP_JSON', '/tmp/task_result_temp.json')
with open(temp_json_path, "w") as f:
    json.dump(result, f)
PYEOF

# Move results to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export complete ==="