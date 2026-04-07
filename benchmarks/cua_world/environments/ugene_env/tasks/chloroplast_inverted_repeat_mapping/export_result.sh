#!/bin/bash
echo "=== Exporting Chloroplast Mapping results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/botany/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/cp_mapping_end.png 2>/dev/null || true

# Extract features using Python
# We parse the GenBank file for annotations, read the FASTA length, and extract LSC/SSC from the report
python3 << PYEOF
import os
import json
import re

RESULTS_DIR = "${RESULTS_DIR}"
gb_file = os.path.join(RESULTS_DIR, "arabidopsis_cp_annotated.gb")
fasta_file = os.path.join(RESULTS_DIR, "IR_sequence.fasta")
report_file = os.path.join(RESULTS_DIR, "cp_structure_report.txt")

out = {
    "task_start": int("${TASK_START}"),
    "gb_exists": os.path.exists(gb_file),
    "gb_valid": False,
    "annotations": [],
    "has_cp_structure_group": False,
    "fasta_exists": os.path.exists(fasta_file),
    "fasta_len": 0,
    "report_exists": os.path.exists(report_file),
    "report_lsc": None,
    "report_ssc": None
}

# Parse GenBank file
if out["gb_exists"]:
    try:
        with open(gb_file, 'r', encoding='utf-8', errors='ignore') as f:
            gb_text = f.read()
        
        if "LOCUS" in gb_text and "ORIGIN" in gb_text:
            out["gb_valid"] = True
            
        if "cp_structure" in gb_text:
            out["has_cp_structure_group"] = True

        # Find Inverted_Repeat annotations
        # Examples: Inverted_Repeat    123..456  OR  Inverted_Repeat    complement(123..456)
        matches = re.finditer(r'Inverted_Repeat\s+(?:complement\()?(\d+)\.\.(\d+)', gb_text, re.IGNORECASE)
        for m in matches:
            out["annotations"].append({
                "start": int(m.group(1)),
                "end": int(m.group(2))
            })
    except Exception as e:
        print(f"Error parsing GB: {e}")

# Parse Extracted FASTA
if out["fasta_exists"]:
    try:
        with open(fasta_file, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            if lines and lines[0].startswith(">"):
                seq = "".join(l.strip() for l in lines[1:])
                out["fasta_len"] = len(seq)
    except Exception as e:
        print(f"Error parsing FASTA: {e}")

# Parse Text Report
if out["report_exists"]:
    try:
        with open(report_file, 'r', encoding='utf-8', errors='ignore') as f:
            report_text = f.read().lower()
            
        # Regex to find numbers near "lsc" or "large single copy"
        lsc_matches = re.findall(r'lsc.*?(\d{4,6})', report_text)
        if not lsc_matches:
            lsc_matches = re.findall(r'large single copy.*?(\d{4,6})', report_text)
            
        # Regex to find numbers near "ssc" or "small single copy"
        ssc_matches = re.findall(r'ssc.*?(\d{4,6})', report_text)
        if not ssc_matches:
            ssc_matches = re.findall(r'small single copy.*?(\d{4,6})', report_text)
            
        if lsc_matches:
            out["report_lsc"] = int(lsc_matches[0])
        if ssc_matches:
            out["report_ssc"] = int(ssc_matches[0])
    except Exception as e:
        print(f"Error parsing report: {e}")

with open("/tmp/cp_mapping_result.json", "w") as f:
    json.dump(out, f, indent=2)
PYEOF

echo "Result data:"
cat /tmp/cp_mapping_result.json
echo "=== Export Complete ==="