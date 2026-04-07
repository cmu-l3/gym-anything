#!/bin/bash
echo "=== Exporting puc19_plasmid_map_export results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/plasmid/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON fields
GB_EXISTS="false"
GB_VALID="false"
GB_MTIME="0"
GB_SIZE="0"
SVG_EXISTS="false"
SVG_VALID="false"
SVG_MTIME="0"
SVG_SIZE="0"

GB_HAS_BLA="false"
GB_HAS_REP="false"
GB_HAS_ECORI="false"
GB_HAS_BAMHI="false"
GB_HAS_HINDIII="false"
GB_LENGTH="0"

# --- Check Annotated GenBank file ---
GB_FILE="${RESULTS_DIR}/pUC19_annotated.gb"
if [ -f "$GB_FILE" ] && [ -s "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    
    # Use python to perform robust regex analysis
    python3 << PYEOF
import json, re

try:
    with open("$GB_FILE", "r") as f:
        content = f.read()

    result = {
        "valid": bool(re.search(r"^LOCUS", content, re.MULTILINE) and re.search(r"ORIGIN", content)),
        "bla": bool(re.search(r"bla|lactamase|ampicillin", content, re.IGNORECASE)),
        "rep": bool(re.search(r"rep_origin|ColE1|origin", content, re.IGNORECASE)),
        "ecori": bool(re.search(r"EcoRI", content, re.IGNORECASE)),
        "bamhi": bool(re.search(r"BamHI", content, re.IGNORECASE)),
        "hindiii": bool(re.search(r"HindIII", content, re.IGNORECASE)),
        "length": 0
    }
    
    # Try to extract length from LOCUS line
    locus_match = re.search(r"^LOCUS\s+\S+\s+(\d+)\s+bp", content, re.MULTILINE)
    if locus_match:
        result["length"] = int(locus_match.group(1))

    with open("/tmp/gb_analysis.json", "w") as f:
        json.dump(result, f)
except Exception as e:
    with open("/tmp/gb_analysis.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

    if [ -f "/tmp/gb_analysis.json" ]; then
        GB_VALID=$(jq -r '.valid // "false"' /tmp/gb_analysis.json)
        GB_HAS_BLA=$(jq -r '.bla // "false"' /tmp/gb_analysis.json)
        GB_HAS_REP=$(jq -r '.rep // "false"' /tmp/gb_analysis.json)
        GB_HAS_ECORI=$(jq -r '.ecori // "false"' /tmp/gb_analysis.json)
        GB_HAS_BAMHI=$(jq -r '.bamhi // "false"' /tmp/gb_analysis.json)
        GB_HAS_HINDIII=$(jq -r '.hindiii // "false"' /tmp/gb_analysis.json)
        GB_LENGTH=$(jq -r '.length // "0"' /tmp/gb_analysis.json)
    fi
fi

# --- Check exported SVG ---
SVG_FILE="${RESULTS_DIR}/pUC19_map.svg"
if [ -f "$SVG_FILE" ] && [ -s "$SVG_FILE" ]; then
    SVG_EXISTS="true"
    SVG_MTIME=$(stat -c %Y "$SVG_FILE" 2>/dev/null || echo "0")
    SVG_SIZE=$(stat -c %s "$SVG_FILE" 2>/dev/null || echo "0")
    
    if head -5 "$SVG_FILE" | grep -qi "<?xml\|<svg"; then
        SVG_VALID="true"
    fi
fi

# Determine if files were created during task timeframe
GB_NEW="false"
SVG_NEW="false"
if [ "$GB_MTIME" -gt "$TASK_START" ]; then GB_NEW="true"; fi
if [ "$SVG_MTIME" -gt "$TASK_START" ]; then SVG_NEW="true"; fi

# Build final output JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "gb_exists": $GB_EXISTS,
    "gb_valid": $GB_VALID,
    "gb_created_during_task": $GB_NEW,
    "gb_size": $GB_SIZE,
    "gb_length": $GB_LENGTH,
    "features_retained_bla": $GB_HAS_BLA,
    "features_retained_rep": $GB_HAS_REP,
    "has_ecori": $GB_HAS_ECORI,
    "has_bamhi": $GB_HAS_BAMHI,
    "has_hindiii": $GB_HAS_HINDIII,
    "svg_exists": $SVG_EXISTS,
    "svg_valid": $SVG_VALID,
    "svg_created_during_task": $SVG_NEW,
    "svg_size": $SVG_SIZE,
    "ugene_running": $(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="