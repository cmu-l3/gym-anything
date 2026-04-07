#!/bin/bash
echo "=== Exporting M. genitalium Proteome Extraction results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"
FASTA_FILE="${RESULTS_DIR}/m_genitalium_proteome.fasta"
REPORT_FILE="${RESULTS_DIR}/extraction_report.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract verification data using a Python script safely within the container
python3 << PYEOF
import json
import os
import re

result = {
    "task_start_ts": int("${TASK_START}" or "0"),
    "fasta_exists": False,
    "fasta_modified_during_task": False,
    "valid_fasta": False,
    "seq_count": 0,
    "is_amino_acid": False,
    "internal_stops": 0,
    "report_exists": False,
    "report_mentions_table4": False,
    "report_mentions_count": False
}

fasta_path = "${FASTA_FILE}"
report_path = "${REPORT_FILE}"

# Check FASTA
if os.path.exists(fasta_path) and os.path.getsize(fasta_path) > 0:
    result["fasta_exists"] = True
    
    # Check modification time
    mtime = os.path.getmtime(fasta_path)
    if mtime > result["task_start_ts"]:
        result["fasta_modified_during_task"] = True

    with open(fasta_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    if content.strip().startswith(">"):
        result["valid_fasta"] = True
        seqs = content.strip().split(">")[1:]
        result["seq_count"] = len(seqs)

        total_internal_stops = 0
        aa_chars = set()
        
        for s in seqs:
            parts = s.split("\n", 1)
            if len(parts) == 2:
                seq_str = parts[1].replace("\n", "").replace(" ", "").upper()
                # Remove trailing stop if present (valid at end of sequence)
                if seq_str.endswith("*"):
                    seq_str = seq_str[:-1]
                
                # Count remaining internal stops
                total_internal_stops += seq_str.count("*")
                aa_chars.update(list(seq_str))

        result["internal_stops"] = total_internal_stops

        # Check if amino acid (contains chars other than standard DNA A,C,G,T,N)
        unique_chars = "".join(aa_chars)
        if re.search(r'[EFILPQ]', unique_chars):
            result["is_amino_acid"] = True

# Check Report
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", encoding="utf-8", errors="ignore") as f:
        report_text = f.read().lower()
        
        if "4" in report_text or "table" in report_text or "mycoplasma" in report_text:
            result["report_mentions_table4"] = True
            
        if str(result["seq_count"]) in report_text and result["seq_count"] > 0:
            result["report_mentions_count"] = True
        elif "47" in report_text: # roughly 470-479
            result["report_mentions_count"] = True

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported JSON verification data. FASTA valid: {result['valid_fasta']}, Seq count: {result['seq_count']}")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="