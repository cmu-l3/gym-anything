#!/bin/bash
echo "=== Exporting HBB Intron Extraction Results ==="

# Record final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULTS_DIR="/home/ga/UGENE_Data/thalassemia_diagnostics/results"
GB_FILE="$RESULTS_DIR/hbb_annotated_with_introns.gb"
FASTA1="$RESULTS_DIR/intron1.fasta"
FASTA2="$RESULTS_DIR/intron2.fasta"
REPORT="$RESULTS_DIR/intron_statistics.txt"

# Process everything in Python and dump the JSON to prevent bash string escape issues
python3 << PYEOF
import json
import os
import re

def safe_read(filepath):
    if os.path.exists(filepath):
        try:
            with open(filepath, 'r') as f:
                return f.read()
        except Exception:
            pass
    return ""

def clean_fasta(content):
    # Removes headers and whitespaces
    lines = content.split('\n')
    seq = "".join([l.strip() for l in lines if not l.startswith('>')])
    return seq.upper()

gb_content = safe_read("$GB_FILE")
f1_content = safe_read("$FASTA1")
f2_content = safe_read("$FASTA2")
report_content = safe_read("$REPORT")

gb_exists = os.path.exists("$GB_FILE")
has_intron_keyword = 'intron' in gb_content.lower()

# Extract coordinates connected to 'intron'
# We extract the entire GB content so the verifier can perform robust regex
gb_content_snippet = gb_content[:10000] if gb_content else ""

f1_seq = clean_fasta(f1_content)
f2_seq = clean_fasta(f2_content)

result = {
    "gb_exists": gb_exists,
    "has_intron_keyword": has_intron_keyword,
    "gb_content": gb_content_snippet,
    "fasta1_exists": os.path.exists("$FASTA1"),
    "fasta1_seq": f1_seq,
    "fasta2_exists": os.path.exists("$FASTA2"),
    "fasta2_seq": f2_seq,
    "report_exists": os.path.exists("$REPORT"),
    "report_content": report_content
}

with open("/tmp/hbb_intron_extraction_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export completed successfully.")
PYEOF