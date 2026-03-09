#!/bin/bash
# export_result.sh - Post-task hook for cascade_emergency_response
# Exports agent's emergency assessment content for verification

echo "=== Exporting cascade_emergency_response result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Check output file
OUTPUT_FILE="/home/ga/Documents/train_derailment_assessment.txt"
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

# TC-101: UN 1050 = Hydrogen Chloride
IDENTIFIES_HCL=0
if echo "$FILE_CONTENT" | grep -qi "hydrogen chloride\|hydrochloric acid\|hcl\|1050"; then
    IDENTIFIES_HCL=1
fi

# TC-102: UN 1005 = Ammonia
IDENTIFIES_NH3=0
if echo "$FILE_CONTENT" | grep -qi "ammonia\|nh3\|1005"; then
    IDENTIFIES_NH3=1
fi

# TC-103: UN 2209 = Formaldehyde
IDENTIFIES_HCHO=0
if echo "$FILE_CONTENT" | grep -qi "formaldehyde\|formalin\|2209"; then
    IDENTIFIES_HCHO=1
fi

# TC-104: UN 1791 = Hypochlorite solution
IDENTIFIES_HYPOCHLORITE=0
if echo "$FILE_CONTENT" | grep -qi "hypochlorite\|bleach\|1791"; then
    IDENTIFIES_HYPOCHLORITE=1
fi

# TC-101 + TC-102 reaction: HCl + NH3 → ammonium chloride (white cloud)
ASSESSES_REACTION=0
if echo "$FILE_CONTENT" | grep -qi "ammonium chloride\|react\|combination\|cloud\|plume\|interact"; then
    ASSESSES_REACTION=1
fi

# Isolation / protective action distances
MENTIONS_ISOLATION=0
if echo "$FILE_CONTENT" | grep -qi "isolation\|evacuat\|distance\|meter\|feet\|mile\|kilometer\|zone"; then
    MENTIONS_ISOLATION=1
fi

# PPE requirements
MENTIONS_PPE=0
if echo "$FILE_CONTENT" | grep -qi "ppe\|scba\|respirator\|protective\|suit\|glove\|level a\|level b"; then
    MENTIONS_PPE=1
fi

# Shelter-in-place or evacuation recommendation
MENTIONS_SHELTER_OR_EVACUATE=0
if echo "$FILE_CONTENT" | grep -qi "shelter.in.place\|shelter in place\|evacuate\|evacuation"; then
    MENTIONS_SHELTER_OR_EVACUATE=1
fi

# Priority actions
MENTIONS_PRIORITY=0
if echo "$FILE_CONTENT" | grep -qi "priority\|immediate\|first\|action\|step"; then
    MENTIONS_PRIORITY=1
fi

echo "Identifies HCl (TC-101): $IDENTIFIES_HCL"
echo "Identifies NH3 (TC-102): $IDENTIFIES_NH3"
echo "Identifies HCHO (TC-103): $IDENTIFIES_HCHO"
echo "Identifies Hypochlorite (TC-104): $IDENTIFIES_HYPOCHLORITE"
echo "Assesses TC-101+TC-102 reaction: $ASSESSES_REACTION"
echo "Mentions isolation distances: $MENTIONS_ISOLATION"
echo "Mentions PPE: $MENTIONS_PPE"
echo "Mentions shelter/evacuate: $MENTIONS_SHELTER_OR_EVACUATE"

# Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Write result JSON
python3 - <<PYEOF
import json

result = {
    "task": "cascade_emergency_response",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "initial_file_existed": $INITIAL_EXISTS,
    "identifies_hcl_tc101": $IDENTIFIES_HCL,
    "identifies_nh3_tc102": $IDENTIFIES_NH3,
    "identifies_formaldehyde_tc103": $IDENTIFIES_HCHO,
    "identifies_hypochlorite_tc104": $IDENTIFIES_HYPOCHLORITE,
    "assesses_tc101_tc102_reaction": $ASSESSES_REACTION,
    "mentions_isolation_distances": $MENTIONS_ISOLATION,
    "mentions_ppe": $MENTIONS_PPE,
    "mentions_shelter_or_evacuate": $MENTIONS_SHELTER_OR_EVACUATE,
    "mentions_priority_actions": $MENTIONS_PRIORITY,
    "elapsed_seconds": $ELAPSED,
}

with open("/tmp/cascade_emergency_response_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/cascade_emergency_response_result.json")
PYEOF

echo "=== Export complete ==="
