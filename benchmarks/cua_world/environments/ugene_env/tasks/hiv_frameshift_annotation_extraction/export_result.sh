#!/bin/bash
echo "=== Exporting HIV Frameshift Annotation results ==="

# Record final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define paths
RESULTS_DIR="/home/ga/UGENE_Data/virology/results"
GB_FILE="$RESULTS_DIR/hiv_annotated.gb"
FASTA_FILE="$RESULTS_DIR/frameshift_region.fasta"
REPORT_FILE="$RESULTS_DIR/frameshift_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to safely parse the output files and generate a JSON result
python3 << PYEOF
import json
import os
import re

res = {
    "task_start_time": $START_TIME,
    "gb_exists": False,
    "gb_size": 0,
    "gb_mtime": 0,
    "has_misc_feature": False,
    "has_note": False,
    "feature_coords": [],
    "fasta_exists": False,
    "fasta_size": 0,
    "fasta_seq_length": 0,
    "fasta_mtime": 0,
    "fasta_content": "",
    "report_exists": False,
    "report_content": ""
}

# Check GenBank file
gb_path = "$GB_FILE"
if os.path.exists(gb_path) and os.path.getsize(gb_path) > 0:
    res["gb_exists"] = True
    res["gb_size"] = os.path.getsize(gb_path)
    res["gb_mtime"] = os.path.getmtime(gb_path)
    
    with open(gb_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        if "misc_feature" in content:
            res["has_misc_feature"] = True
        if "gag_pol_overlap" in content:
            res["has_note"] = True
            
        # Try to extract the coordinates of the misc_feature near gag_pol_overlap
        # Pattern matching typical GenBank feature blocks
        blocks = content.split("misc_feature")
        for b in blocks[1:]:
            if "gag_pol_overlap" in b:
                # The first line of the block usually has the coordinates
                coords_match = re.search(r'(\d+\.\.\d+)', b)
                if coords_match:
                    res["feature_coords"].append(coords_match.group(1))

# Check FASTA file
fasta_path = "$FASTA_FILE"
if os.path.exists(fasta_path) and os.path.getsize(fasta_path) > 0:
    res["fasta_exists"] = True
    res["fasta_size"] = os.path.getsize(fasta_path)
    res["fasta_mtime"] = os.path.getmtime(fasta_path)
    
    with open(fasta_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        seq = "".join([l.strip() for l in lines if not l.startswith(">")])
        res["fasta_seq_length"] = len(seq)
        res["fasta_content"] = seq[:50]  # Just take the first 50 chars for verification

# Check Report file
report_path = "$REPORT_FILE"
if os.path.exists(report_path) and os.path.getsize(report_path) > 0:
    res["report_exists"] = True
    with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
        res["report_content"] = f.read()[:500]  # Take first 500 chars

# Export JSON securely
with open("/tmp/hiv_frameshift_result.json", "w") as f:
    json.dump(res, f)

PYEOF

chmod 666 /tmp/hiv_frameshift_result.json
echo "Result exported to /tmp/hiv_frameshift_result.json"
cat /tmp/hiv_frameshift_result.json
echo "=== Export complete ==="