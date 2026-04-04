#!/bin/bash
# export_result.sh - Post-task hook for storage_segregation_audit
# Exports agent's audit report content for verification

echo "=== Exporting storage_segregation_audit result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot for evidence
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Check if the output file exists
OUTPUT_FILE="/home/ga/Documents/storage_audit_report.txt"
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
echo "File lines: $FILE_LINES"

# Check for specific dangerous pairs and keywords
# Pair 1: Sulfuric Acid + Sodium Cyanide (HCN gas generation)
MENTIONS_SULFURIC=0
MENTIONS_CYANIDE=0
if echo "$FILE_CONTENT" | grep -qi "sulfuric\|h2so4\|sulphuric"; then
    MENTIONS_SULFURIC=1
fi
if echo "$FILE_CONTENT" | grep -qi "cyanide\|nacn\|sodium cyanide"; then
    MENTIONS_CYANIDE=1
fi

# Pair 2: Hydrogen Peroxide + Acetone (explosive peroxides)
MENTIONS_PEROXIDE=0
MENTIONS_ACETONE=0
if echo "$FILE_CONTENT" | grep -qi "hydrogen peroxide\|peroxide\|h2o2"; then
    MENTIONS_PEROXIDE=1
fi
if echo "$FILE_CONTENT" | grep -qi "acetone"; then
    MENTIONS_ACETONE=1
fi

# Check for storage recommendations / segregation guidance
MENTIONS_RECOMMENDATIONS=0
if echo "$FILE_CONTENT" | grep -qi "recommend\|segregat\|separate\|incompatible\|must not\|do not store"; then
    MENTIONS_RECOMMENDATIONS=1
fi

# Check for Chlorine + Ammonia pair
MENTIONS_CHLORINE=0
MENTIONS_AMMONIA=0
if echo "$FILE_CONTENT" | grep -qi "chlorine\|cl2"; then
    MENTIONS_CHLORINE=1
fi
if echo "$FILE_CONTENT" | grep -qi "ammonia\|nh3"; then
    MENTIONS_AMMONIA=1
fi

# Check for nitric acid + organic reactivity
MENTIONS_NITRIC=0
if echo "$FILE_CONTENT" | grep -qi "nitric acid\|hno3"; then
    MENTIONS_NITRIC=1
fi

# Check for sodium azide
MENTIONS_AZIDE=0
if echo "$FILE_CONTENT" | grep -qi "azide\|sodium azide"; then
    MENTIONS_AZIDE=1
fi

# Check for CAMEO Chemicals as the reference source
MENTIONS_CAMEO=0
if echo "$FILE_CONTENT" | grep -qi "cameo\|noaa\|cameochemicals"; then
    MENTIONS_CAMEO=1
fi

# Count dangerous pairs identified
PAIRS_FOUND=0
if [ "$MENTIONS_CHLORINE" -eq 1 ] && [ "$MENTIONS_AMMONIA" -eq 1 ]; then
    PAIRS_FOUND=$((PAIRS_FOUND + 1))
fi
if [ "$MENTIONS_NITRIC" -eq 1 ]; then
    PAIRS_FOUND=$((PAIRS_FOUND + 1))
fi
if [ "$MENTIONS_AZIDE" -eq 1 ]; then
    PAIRS_FOUND=$((PAIRS_FOUND + 1))
fi

echo "Mentions sulfuric acid: $MENTIONS_SULFURIC"
echo "Mentions cyanide: $MENTIONS_CYANIDE"
echo "Mentions peroxide: $MENTIONS_PEROXIDE"
echo "Mentions acetone: $MENTIONS_ACETONE"
echo "Has recommendations: $MENTIONS_RECOMMENDATIONS"
echo "Additional pairs found: $PAIRS_FOUND"

# Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Truncate content for JSON (avoid huge payloads)
CONTENT_PREVIEW=$(echo "$FILE_CONTENT" | head -100 | python3 -c "
import sys, json
data = sys.stdin.read()
print(json.dumps(data))
" 2>/dev/null || echo '""')

# Write result JSON
python3 - <<PYEOF
import json

result = {
    "task": "storage_segregation_audit",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "initial_file_existed": $INITIAL_EXISTS,
    "mentions_sulfuric": $MENTIONS_SULFURIC,
    "mentions_cyanide": $MENTIONS_CYANIDE,
    "mentions_peroxide": $MENTIONS_PEROXIDE,
    "mentions_acetone": $MENTIONS_ACETONE,
    "has_recommendations": $MENTIONS_RECOMMENDATIONS,
    "additional_pairs_found": $PAIRS_FOUND,
    "mentions_chlorine": $MENTIONS_CHLORINE,
    "mentions_ammonia": $MENTIONS_AMMONIA,
    "mentions_nitric": $MENTIONS_NITRIC,
    "mentions_azide": $MENTIONS_AZIDE,
    "mentions_cameo": $MENTIONS_CAMEO,
    "elapsed_seconds": $ELAPSED,
}

with open("/tmp/storage_segregation_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/storage_segregation_audit_result.json")
PYEOF

echo "=== Export complete ==="
