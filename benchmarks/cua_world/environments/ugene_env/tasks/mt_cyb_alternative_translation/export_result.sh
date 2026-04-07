#!/bin/bash
echo "=== Exporting mt_cyb_alternative_translation results ==="

TASK_START=$(cat /tmp/mt_cyb_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Extract verification data using Python
python3 << PYEOF
import json
import os
import re

task_start = int("${TASK_START}")
results_dir = "${RESULTS_DIR}"

result = {
    "gb_exists": False,
    "gb_created_during_task": False,
    "gb_valid": False,
    "gb_has_features": False,
    "fasta_exists": False,
    "fasta_created_during_task": False,
    "fasta_valid": False,
    "protein_length": 0,
    "internal_stop_count": -1,
    "report_exists": False,
    "report_mentions_table": False,
    "report_mentions_length": False,
    "report_mentions_stop_context": False
}

# Check GenBank file
gb_path = os.path.join(results_dir, "mt_cyb_annotated.gb")
if os.path.isfile(gb_path):
    result["gb_exists"] = True
    mtime = os.path.getmtime(gb_path)
    if mtime >= task_start:
        result["gb_created_during_task"] = True
        
    with open(gb_path, 'r', errors='ignore') as f:
        content = f.read()
        if "LOCUS" in content and "ORIGIN" in content:
            result["gb_valid"] = True
        if "FEATURES" in content and ("CDS" in content or "misc_feature" in content or "ORF" in content):
            result["gb_has_features"] = True

# Check FASTA file
fasta_path = os.path.join(results_dir, "mt_cyb_protein.fasta")
if os.path.isfile(fasta_path):
    result["fasta_exists"] = True
    mtime = os.path.getmtime(fasta_path)
    if mtime >= task_start:
        result["fasta_created_during_task"] = True
        
    with open(fasta_path, 'r', errors='ignore') as f:
        content = f.read().strip()
        
    if content.startswith(">"):
        result["fasta_valid"] = True
        # Extract sequences
        seq_blocks = content.split(">")[1:]
        longest_seq = ""
        for block in seq_blocks:
            lines = block.split("\n", 1)
            if len(lines) > 1:
                seq = re.sub(r'\s+', '', lines[1]).upper()
                if len(seq) > len(longest_seq):
                    longest_seq = seq
        
        if longest_seq:
            result["protein_length"] = len(longest_seq)
            # Count internal stops. Disregard trailing stop if present.
            seq_to_check = longest_seq[:-1] if longest_seq.endswith("*") else longest_seq
            result["internal_stop_count"] = seq_to_check.count("*")

# Check Report
report_path = os.path.join(results_dir, "translation_report.txt")
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, 'r', errors='ignore') as f:
        content = f.read().lower()
        if "vertebrate mitochondrial" in content or "mitochondrial" in content:
            result["report_mentions_table"] = True
        if "380" in content or "379" in content or "381" in content or "378" in content:
            result["report_mentions_length"] = True
        if "stop" in content or "tga" in content or "tryptophan" in content:
            result["report_mentions_stop_context"] = True

with open("/tmp/mt_cyb_translation_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Verification data extracted to /tmp/mt_cyb_translation_result.json"
cat /tmp/mt_cyb_translation_result.json
echo "=== Export complete ==="