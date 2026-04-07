#!/bin/bash
echo "=== Exporting insulin_mature_chain_extraction result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to safely parse FASTA outputs, verify metadata, and export JSON
python3 << PYEOF
import json
import os
import re

RESULTS_DIR = "/home/ga/UGENE_Data/chains"
TASK_START = $TASK_START

def parse_fasta(filename):
    path = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(path):
        return {"exists": False, "header": "", "seq": "", "length": 0, "mtime": 0}
    
    mtime = os.path.getmtime(path)
    with open(path, "r", errors="ignore") as f:
        lines = f.readlines()
        
    if not lines:
        return {"exists": True, "header": "", "seq": "", "length": 0, "mtime": mtime}
        
    header = lines[0].strip()
    # Strip whitespace, newlines, and any trailing asterisks (often added during translation as stop codons)
    seq = "".join(l.strip() for l in lines[1:] if not l.startswith(">")).upper().rstrip("*")
    
    return {"exists": True, "header": header, "seq": seq, "length": len(seq), "mtime": mtime}

result = {
    "task_start": TASK_START,
    "task_end": $TASK_END,
    "A_nt": parse_fasta("insulin_A_nt.fasta"),
    "A_aa": parse_fasta("insulin_A_aa.fasta"),
    "B_nt": parse_fasta("insulin_B_nt.fasta"),
    "B_aa": parse_fasta("insulin_B_aa.fasta"),
}

report_path = os.path.join(RESULTS_DIR, "chain_report.txt")
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="ignore") as f:
        result["report_content"] = f.read()[:1000]
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Write safely to /tmp
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="