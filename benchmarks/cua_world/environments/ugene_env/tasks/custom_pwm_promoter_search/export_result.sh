#!/bin/bash
echo "=== Exporting custom_pwm_promoter_search results ==="

RESULTS_DIR="/home/ga/UGENE_Data/promoters/results"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute a Python script to robustly gather output file statistics
python3 << PYEOF
import os
import json
import glob

results_dir = "${RESULTS_DIR}"
task_start = ${TASK_START}
task_end = ${TASK_END}

output = {
    "task_start": task_start,
    "task_end": task_end,
    "matrix_exists": False,
    "matrix_is_valid": False,
    "matrix_created_during_task": False,
    "gff_exists": False,
    "gff_hit_count": 0,
    "gff_created_during_task": False,
    "report_exists": False,
    "report_mentions_85": False,
    "report_hit_count": 0,
    "report_created_during_task": False
}

if not os.path.exists(results_dir):
    with open("/tmp/task_result.json", "w") as f:
        json.dump(output, f)
    exit(0)

# 1. Check Matrix File
matrix_files = glob.glob(os.path.join(results_dir, "*.pwm")) + \
               glob.glob(os.path.join(results_dir, "*.pfm")) + \
               glob.glob(os.path.join(results_dir, "*.profile"))

if matrix_files:
    matrix_path = matrix_files[0]
    output["matrix_exists"] = True
    mtime = os.path.getmtime(matrix_path)
    output["matrix_created_during_task"] = mtime >= task_start
    
    # Try to validate basic matrix structure (should have 4 rows for A,C,G,T and ~15 columns)
    with open(matrix_path, 'r') as f:
        content = f.read().upper()
        # Count rows that look like nucleotide rows
        num_rows = sum(1 for line in content.split('\\n') if any(line.startswith(n) for n in ['A', 'C', 'G', 'T']))
        # Just check if it's reasonably sized to be a matrix for a 15bp motif
        if len(content.split()) >= 15 * 4:
            output["matrix_is_valid"] = True

# 2. Check GFF3 File
gff_path = os.path.join(results_dir, "predicted_promoters.gff")
if os.path.exists(gff_path):
    output["gff_exists"] = True
    mtime = os.path.getmtime(gff_path)
    output["gff_created_during_task"] = mtime >= task_start
    
    with open(gff_path, 'r') as f:
        lines = f.readlines()
        # Count non-comment lines as hits
        hits = [l for l in lines if not l.startswith('#') and l.strip()]
        output["gff_hit_count"] = len(hits)

# 3. Check Report File
report_path = os.path.join(results_dir, "search_summary.txt")
if os.path.exists(report_path):
    output["report_exists"] = True
    mtime = os.path.getmtime(report_path)
    output["report_created_during_task"] = mtime >= task_start
    
    with open(report_path, 'r') as f:
        content = f.read().lower()
        if '85%' in content or '85 percent' in content or 'threshold: 85' in content:
            output["report_mentions_85"] = True
            
        import re
        # Try to find numbers in the report representing hit counts
        numbers = re.findall(r'\\b\\d+\\b', content)
        if numbers:
            # Assuming the agent reports >0 hits if successful
            hits = [int(n) for n in numbers if int(n) != 85]
            if hits:
                output["report_hit_count"] = max(hits)

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Exported results:"
cat /tmp/task_result.json

echo "=== Export complete ==="