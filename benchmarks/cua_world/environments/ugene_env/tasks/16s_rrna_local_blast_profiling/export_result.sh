#!/bin/bash
echo "=== Exporting 16s_rrna_local_blast_profiling results ==="

# Record end time and take a final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse outputs robustly using Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json
import os
import re

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_files_exist": False,
    "gb_exists": False,
    "gb_size_bytes": 0,
    "gb_seq_length": 0,
    "feature_count": 0,
    "feature_coords": [],
    "report_exists": False,
    "report_mentions_7": False
}

# Check for BLAST Database files
blast_dir = "/home/ga/UGENE_Data/blast/"
if os.path.exists(blast_dir):
    db_exts = ['.nhr', '.nin', '.nsq', '.ndb', '.not', '.ntf', '.nto']
    db_files = [f for f in os.listdir(blast_dir) if any(f.endswith(ext) for ext in db_exts)]
    if len(db_files) >= 2:
        result["db_files_exist"] = True

# Check exported GenBank file
gb_path = "/home/ga/UGENE_Data/blast/results/ecoli_16s_annotated.gb"
if os.path.exists(gb_path) and os.path.getsize(gb_path) > 0:
    result["gb_exists"] = True
    result["gb_size_bytes"] = os.path.getsize(gb_path)
    
    with open(gb_path, 'r', errors='ignore') as f:
        content = f.read()
        
        # Determine sequence length from LOCUS line
        locus_match = re.search(r'LOCUS\s+\S+\s+(\d+)\s+bp', content)
        if locus_match:
            result["gb_seq_length"] = int(locus_match.group(1))
            
        # Count features and extract coordinates (ignoring 'source' feature)
        lines = content.split('\n')
        in_features = False
        coords = []
        for line in lines:
            if line.startswith('FEATURES'):
                in_features = True
                continue
            if line.startswith('ORIGIN'):
                break
            # Features typically start with 5 spaces in GenBank files
            if in_features and line.startswith('     ') and len(line) > 5 and line[5] != ' ' and not line.startswith('     source'):
                # Extract first coordinate
                match = re.search(r'(\d+)', line)
                if match:
                    coords.append(int(match.group(1)))
                    
        result["feature_count"] = len(coords)
        result["feature_coords"] = coords

# Check the user report
report_path = "/home/ga/UGENE_Data/blast/results/16s_blast_report.txt"
if os.path.exists(report_path) and os.path.getsize(report_path) > 0:
    result["report_exists"] = True
    with open(report_path, 'r', errors='ignore') as f:
        text = f.read().lower()
        if '7' in text or 'seven' in text:
            result["report_mentions_7"] = True

# Write evaluation state
with open("$TEMP_JSON", "w") as f:
    json.dump(result, f)
PYEOF

# Move JSON into final spot and manage permissions cleanly
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="