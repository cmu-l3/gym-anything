#!/bin/bash
# export_result.sh - Post-task hook for process_hazard_review
# Exports agent's PHA report for verification

echo "=== Exporting process_hazard_review result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Check output file
OUTPUT_FILE="/home/ga/Documents/process_hazard_report.txt"
INITIAL_EXISTS=$(cat /tmp/initial_output_file_exists 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_LINES=$(wc -l < "$OUTPUT_FILE")
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
else
    FILE_EXISTS=0
    FILE_SIZE=0
    FILE_LINES=0
    FILE_CONTENT=""
fi

echo "Output file exists: $FILE_EXISTS"
echo "File size: $FILE_SIZE bytes"

# Check for Acrylic Acid + NaOH pair (violent exotherm / polymerization risk)
MENTIONS_ACRYLIC_ACID=0
MENTIONS_NAOH=0
if echo "$FILE_CONTENT" | grep -qi "acrylic acid\|acrylate"; then
    MENTIONS_ACRYLIC_ACID=1
fi
if echo "$FILE_CONTENT" | grep -qi "sodium hydroxide\|naoh\|caustic\|lye"; then
    MENTIONS_NAOH=1
fi

# Check for the acrylic acid + NaOH reaction being flagged as hazardous
ACRYLIC_NAOH_HAZARD=0
if [ "$MENTIONS_ACRYLIC_ACID" -eq 1 ] && [ "$MENTIONS_NAOH" -eq 1 ]; then
    if echo "$FILE_CONTENT" | grep -qi "exotherm\|violent\|polymeriz\|hazard\|react"; then
        ACRYLIC_NAOH_HAZARD=1
    fi
fi

# Check for Methanol + H2SO4 pair
MENTIONS_METHANOL=0
MENTIONS_H2SO4=0
if echo "$FILE_CONTENT" | grep -qi "methanol\|methyl alcohol"; then
    MENTIONS_METHANOL=1
fi
if echo "$FILE_CONTENT" | grep -qi "sulfuric acid\|h2so4\|sulphuric"; then
    MENTIONS_H2SO4=1
fi

METHANOL_H2SO4_HAZARD=0
if [ "$MENTIONS_METHANOL" -eq 1 ] && [ "$MENTIONS_H2SO4" -eq 1 ]; then
    if echo "$FILE_CONTENT" | grep -qi "exotherm\|react\|hazard\|dimethyl ether\|ether"; then
        METHANOL_H2SO4_HAZARD=1
    fi
fi

# Check for identification of Building 12 ventilation safety gap
IDENTIFIES_VENTILATION_GAP=0
if echo "$FILE_CONTENT" | grep -qi "ventilat\|explosion.proof\|building 12\|flammable\|vapor"; then
    IDENTIFIES_VENTILATION_GAP=1
fi

# Check for use of CAMEO Reactivity tool
MENTIONS_REACTIVITY=0
if echo "$FILE_CONTENT" | grep -qi "reactivity\|reactive group\|cameo\|react tool\|incompatible"; then
    MENTIONS_REACTIVITY=1
fi

# Check for safeguard recommendations
MENTIONS_SAFEGUARDS=0
if echo "$FILE_CONTENT" | grep -qi "safeguard\|recommend\|control\|engineer\|prevent\|mitigat\|interloc"; then
    MENTIONS_SAFEGUARDS=1
fi

# Check for process-specific content (mentions all 5 chemicals)
MENTIONS_TOLUENE=0
if echo "$FILE_CONTENT" | grep -qi "toluene"; then
    MENTIONS_TOLUENE=1
fi

CHEMICALS_COUNT=0
for v in $MENTIONS_ACRYLIC_ACID $MENTIONS_H2SO4 $MENTIONS_METHANOL $MENTIONS_NAOH $MENTIONS_TOLUENE; do
    if [ "$v" -eq 1 ]; then
        CHEMICALS_COUNT=$((CHEMICALS_COUNT + 1))
    fi
done

echo "Mentions acrylic acid: $MENTIONS_ACRYLIC_ACID"
echo "Mentions NaOH: $MENTIONS_NAOH"
echo "Acrylic Acid + NaOH hazard flagged: $ACRYLIC_NAOH_HAZARD"
echo "Methanol + H2SO4 hazard flagged: $METHANOL_H2SO4_HAZARD"
echo "Identifies ventilation gap: $IDENTIFIES_VENTILATION_GAP"
echo "Mentions CAMEO reactivity: $MENTIONS_REACTIVITY"
echo "Includes safeguards: $MENTIONS_SAFEGUARDS"
echo "Chemicals mentioned: $CHEMICALS_COUNT / 5"

# Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Write result JSON
python3 - <<PYEOF
import json

result = {
    "task": "process_hazard_review",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "initial_file_existed": $INITIAL_EXISTS,
    "mentions_acrylic_acid": $MENTIONS_ACRYLIC_ACID,
    "mentions_naoh": $MENTIONS_NAOH,
    "acrylic_naoh_hazard_flagged": $ACRYLIC_NAOH_HAZARD,
    "mentions_methanol": $MENTIONS_METHANOL,
    "mentions_h2so4": $MENTIONS_H2SO4,
    "methanol_h2so4_hazard_flagged": $METHANOL_H2SO4_HAZARD,
    "identifies_ventilation_gap": $IDENTIFIES_VENTILATION_GAP,
    "mentions_reactivity_tool": $MENTIONS_REACTIVITY,
    "includes_safeguards": $MENTIONS_SAFEGUARDS,
    "chemicals_mentioned": $CHEMICALS_COUNT,
    "elapsed_seconds": $ELAPSED,
}

with open("/tmp/process_hazard_review_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/process_hazard_review_result.json")
PYEOF

echo "=== Export complete ==="
