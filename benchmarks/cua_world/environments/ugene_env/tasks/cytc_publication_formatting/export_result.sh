#!/bin/bash
echo "=== Exporting cytc_publication_formatting result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize variables
FASTA_EXISTS="false"
FASTA_SEQ_COUNT=0
FASTA_HAS_PLANTS="false"
FASTA_IS_ALIGNED="false"

HTML_EXISTS="false"
HTML_HAS_COLORS="false"
HTML_HAS_ANIMALS="false"

REPORT_EXISTS="false"
REPORT_MENTIONS_MUSCLE="false"
REPORT_MENTIONS_ZAPPO="false"
REPORT_MENTIONS_5="false"

# 1. Check FASTA Alignment
FASTA_FILE="${RESULTS_DIR}/animal_cytc_alignment.fasta"
if [ -f "$FASTA_FILE" ] && [ -s "$FASTA_FILE" ]; then
    FASTA_EXISTS="true"
    FASTA_SEQ_COUNT=$(grep -c "^>" "$FASTA_FILE" 2>/dev/null || echo "0")
    
    # Check if plants/fungi were successfully removed
    if grep -q "P00053\|P00048\|P00044" "$FASTA_FILE" 2>/dev/null; then
        FASTA_HAS_PLANTS="true"
    fi
    
    # Check if alignment was performed (gaps present)
    if grep -v "^>" "$FASTA_FILE" 2>/dev/null | grep -q "-"; then
        FASTA_IS_ALIGNED="true"
    fi
fi

# 2. Check HTML Export
HTML_FILE="${RESULTS_DIR}/animal_cytc_alignment.html"
if [ -f "$HTML_FILE" ] && [ -s "$HTML_FILE" ]; then
    HTML_EXISTS="true"
    
    # Check for color styling (proves Zappo or similar scheme was active)
    if grep -qi "bgcolor=\|background-color:\|rgb(" "$HTML_FILE" 2>/dev/null; then
        HTML_HAS_COLORS="true"
    fi
    
    # Check if at least some animal accession IDs are in the HTML
    if grep -q "P99999" "$HTML_FILE" 2>/dev/null || grep -q "P67881" "$HTML_FILE" 2>/dev/null; then
        HTML_HAS_ANIMALS="true"
    fi
fi

# 3. Check Report Text
REPORT_FILE="${RESULTS_DIR}/publication_report.txt"
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    grep -qi "MUSCLE" "$REPORT_FILE" 2>/dev/null && REPORT_MENTIONS_MUSCLE="true"
    grep -qi "Zappo" "$REPORT_FILE" 2>/dev/null && REPORT_MENTIONS_ZAPPO="true"
    grep -qw "5" "$REPORT_FILE" 2>/dev/null && REPORT_MENTIONS_5="true"
fi

# Dump JSON for Python verifier
python3 << PYEOF
import json

result = {
    "task_start": int("$TASK_START"),
    "task_end": int("$TASK_END"),
    "fasta_exists": "$FASTA_EXISTS" == "true",
    "fasta_seq_count": int("$FASTA_SEQ_COUNT"),
    "fasta_has_plants": "$FASTA_HAS_PLANTS" == "true",
    "fasta_is_aligned": "$FASTA_IS_ALIGNED" == "true",
    "html_exists": "$HTML_EXISTS" == "true",
    "html_has_colors": "$HTML_HAS_COLORS" == "true",
    "html_has_animals": "$HTML_HAS_ANIMALS" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_mentions_muscle": "$REPORT_MENTIONS_MUSCLE" == "true",
    "report_mentions_zappo": "$REPORT_MENTIONS_ZAPPO" == "true",
    "report_mentions_5": "$REPORT_MENTIONS_5" == "true"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="