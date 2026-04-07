#!/bin/bash
echo "=== Exporting microrna_structure_folding results ==="

RESULTS_DIR="/home/ga/UGENE_Data/rna/results"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check GenBank file
GB_FILE="${RESULTS_DIR}/mirna_structures.gb"
GB_EXISTS=false
GB_VALID=false
GB_SEQ_COUNT=0
GB_HAS_STRUCTURE=false

if [ -f "$GB_FILE" ] && [ -s "$GB_FILE" ]; then
    GB_EXISTS=true
    if grep -q "^LOCUS" "$GB_FILE" && grep -q "^ORIGIN" "$GB_FILE"; then
        GB_VALID=true
        GB_SEQ_COUNT=$(grep -c "^LOCUS" "$GB_FILE")
        
        # Check for secondary_structure annotation or notes with bracket notation
        if grep -qi "secondary_structure\|note.*\(.*\.\|note.*\..*\(" "$GB_FILE"; then
            GB_HAS_STRUCTURE=true
        fi
    fi
fi

# Check report file
REPORT_FILE="${RESULTS_DIR}/mfe_report.txt"
REPORT_EXISTS=false
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    # Read up to 200 lines, convert to base64 to avoid JSON encoding issues
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 200 | base64 -w 0)
fi

# Build JSON using Python
python3 << PYEOF
import json

result = {
    "gb_exists": "${GB_EXISTS}" == "true",
    "gb_valid": "${GB_VALID}" == "true",
    "gb_seq_count": int("${GB_SEQ_COUNT}" or "0"),
    "gb_has_structure": "${GB_HAS_STRUCTURE}" == "true",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_content_b64": "${REPORT_CONTENT}"
}

with open("/tmp/microrna_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="