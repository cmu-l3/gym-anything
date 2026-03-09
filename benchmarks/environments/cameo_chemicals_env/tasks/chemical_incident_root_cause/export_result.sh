#!/bin/bash
# export_result.sh - Post-task hook for chemical_incident_root_cause
# Exports agent's root cause investigation report for verification

echo "=== Exporting chemical_incident_root_cause result ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Check output file
OUTPUT_FILE="/home/ga/Documents/incident_root_cause_report.txt"
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

# Check identification of toluene + nitric acid as root cause
MENTIONS_TOLUENE=0
MENTIONS_NITRIC_ACID=0
if echo "$FILE_CONTENT" | grep -qi "toluene"; then
    MENTIONS_TOLUENE=1
fi
if echo "$FILE_CONTENT" | grep -qi "nitric acid\|hno3"; then
    MENTIONS_NITRIC_ACID=1
fi

# Check for nitration reaction explanation
IDENTIFIES_NITRATION=0
if echo "$FILE_CONTENT" | grep -qi "nitrat\|nitrotoluene\|tnt\|trinitrotoluene\|explosive\|oxidiz\|exotherm"; then
    IDENTIFIES_NITRATION=1
fi

# Full root cause: toluene + nitric acid + nitration mentioned
ROOT_CAUSE_CORRECT=0
if [ "$MENTIONS_TOLUENE" -eq 1 ] && [ "$MENTIONS_NITRIC_ACID" -eq 1 ] && [ "$IDENTIFIES_NITRATION" -eq 1 ]; then
    ROOT_CAUSE_CORRECT=1
fi

# Evaluation of H2O2 alternative
EVALUATES_H2O2=0
if echo "$FILE_CONTENT" | grep -qi "hydrogen peroxide\|h2o2\|peroxide"; then
    EVALUATES_H2O2=1
fi

H2O2_VERDICT_INCOMPATIBLE=0
if [ "$EVALUATES_H2O2" -eq 1 ]; then
    if echo "$FILE_CONTENT" | grep -qi "incompatible\|hazard\|react\|oxidiz\|unsafe\|dangerous"; then
        H2O2_VERDICT_INCOMPATIBLE=1
    fi
fi

# Evaluation of KMnO4 alternative
EVALUATES_KMNO4=0
if echo "$FILE_CONTENT" | grep -qi "potassium permanganate\|kmno4\|permanganate"; then
    EVALUATES_KMNO4=1
fi

KMNO4_VERDICT_INCOMPATIBLE=0
if [ "$EVALUATES_KMNO4" -eq 1 ]; then
    if echo "$FILE_CONTENT" | grep -qi "incompatible\|hazard\|react\|oxidiz\|unsafe\|dangerous"; then
        KMNO4_VERDICT_INCOMPATIBLE=1
    fi
fi

# Preventive measures
MENTIONS_PREVENTION=0
if echo "$FILE_CONTENT" | grep -qi "prevent\|purge\|degas\|inert\|safeguard\|procedure\|protocol\|control"; then
    MENTIONS_PREVENTION=1
fi

# Check for root cause analysis structure
MENTIONS_ROOT_CAUSE=0
if echo "$FILE_CONTENT" | grep -qi "root cause\|cause\|mechanism\|explanation\|finding"; then
    MENTIONS_ROOT_CAUSE=1
fi

echo "Mentions toluene: $MENTIONS_TOLUENE"
echo "Mentions nitric acid: $MENTIONS_NITRIC_ACID"
echo "Identifies nitration: $IDENTIFIES_NITRATION"
echo "Root cause correct: $ROOT_CAUSE_CORRECT"
echo "Evaluates H2O2: $EVALUATES_H2O2"
echo "H2O2 verdict incompatible: $H2O2_VERDICT_INCOMPATIBLE"
echo "Evaluates KMnO4: $EVALUATES_KMNO4"
echo "KMnO4 verdict incompatible: $KMNO4_VERDICT_INCOMPATIBLE"
echo "Mentions prevention: $MENTIONS_PREVENTION"

# Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Write result JSON
python3 - <<PYEOF
import json

result = {
    "task": "chemical_incident_root_cause",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_lines": $FILE_LINES,
    "initial_file_existed": $INITIAL_EXISTS,
    "mentions_toluene": $MENTIONS_TOLUENE,
    "mentions_nitric_acid": $MENTIONS_NITRIC_ACID,
    "identifies_nitration": $IDENTIFIES_NITRATION,
    "root_cause_correct": $ROOT_CAUSE_CORRECT,
    "evaluates_h2o2": $EVALUATES_H2O2,
    "h2o2_verdict_incompatible": $H2O2_VERDICT_INCOMPATIBLE,
    "evaluates_kmno4": $EVALUATES_KMNO4,
    "kmno4_verdict_incompatible": $KMNO4_VERDICT_INCOMPATIBLE,
    "mentions_prevention": $MENTIONS_PREVENTION,
    "mentions_root_cause": $MENTIONS_ROOT_CAUSE,
    "elapsed_seconds": $ELAPSED,
}

with open("/tmp/chemical_incident_root_cause_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/chemical_incident_root_cause_result.json")
PYEOF

echo "=== Export complete ==="
