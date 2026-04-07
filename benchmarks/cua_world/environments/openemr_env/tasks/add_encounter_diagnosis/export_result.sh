#!/bin/bash
# Export script for Add Encounter Diagnosis task

echo "=== Exporting Add Encounter Diagnosis Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=2

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_DX_COUNT=$(cat /tmp/initial_dx_count.txt 2>/dev/null || echo "0")
INITIAL_COPD_COUNT=$(cat /tmp/initial_copd_count.txt 2>/dev/null || echo "0")
TARGET_ENCOUNTER=$(cat /tmp/target_encounter.txt 2>/dev/null || echo "0")

# Get current diagnosis counts
CURRENT_DX_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type='ICD10' AND activity=1" 2>/dev/null || echo "0")
CURRENT_COPD_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type='ICD10' AND code LIKE 'J44%' AND activity=1" 2>/dev/null || echo "0")

echo "Diagnosis counts: initial_dx=$INITIAL_DX_COUNT, current_dx=$CURRENT_DX_COUNT"
echo "COPD code counts: initial=$INITIAL_COPD_COUNT, current=$CURRENT_COPD_COUNT"

# Debug: Show all billing records for patient
echo ""
echo "=== DEBUG: All billing records for patient ==="
openemr_query "SELECT id, pid, encounter, code_type, code, code_text, activity FROM billing WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for COPD diagnosis codes (J44.x)
echo "Checking for J44.x COPD codes..."
COPD_CODE_DATA=$(openemr_query "SELECT id, pid, encounter, code_type, code, code_text, activity FROM billing WHERE pid=$PATIENT_PID AND code_type='ICD10' AND code LIKE 'J44%' AND activity=1 ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse COPD code data
COPD_CODE_FOUND="false"
COPD_CODE_ID=""
COPD_CODE_ENCOUNTER=""
COPD_CODE_VALUE=""
COPD_CODE_TEXT=""
COPD_CODE_ACTIVE=""

if [ -n "$COPD_CODE_DATA" ]; then
    COPD_CODE_FOUND="true"
    COPD_CODE_ID=$(echo "$COPD_CODE_DATA" | cut -f1)
    COPD_CODE_PID=$(echo "$COPD_CODE_DATA" | cut -f2)
    COPD_CODE_ENCOUNTER=$(echo "$COPD_CODE_DATA" | cut -f3)
    COPD_CODE_TYPE=$(echo "$COPD_CODE_DATA" | cut -f4)
    COPD_CODE_VALUE=$(echo "$COPD_CODE_DATA" | cut -f5)
    COPD_CODE_TEXT=$(echo "$COPD_CODE_DATA" | cut -f6)
    COPD_CODE_ACTIVE=$(echo "$COPD_CODE_DATA" | cut -f7)
    
    echo "COPD code found:"
    echo "  ID: $COPD_CODE_ID"
    echo "  Patient: $COPD_CODE_PID"
    echo "  Encounter: $COPD_CODE_ENCOUNTER"
    echo "  Code: $COPD_CODE_VALUE"
    echo "  Text: $COPD_CODE_TEXT"
    echo "  Active: $COPD_CODE_ACTIVE"
else
    echo "No J44.x COPD code found for patient"
fi

# Check if code is linked to an encounter
CODE_LINKED_TO_ENCOUNTER="false"
if [ -n "$COPD_CODE_ENCOUNTER" ] && [ "$COPD_CODE_ENCOUNTER" != "0" ] && [ "$COPD_CODE_ENCOUNTER" != "" ]; then
    # Verify the encounter exists
    ENCOUNTER_EXISTS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID AND encounter=$COPD_CODE_ENCOUNTER" 2>/dev/null || echo "0")
    if [ "$ENCOUNTER_EXISTS" -gt 0 ]; then
        CODE_LINKED_TO_ENCOUNTER="true"
        echo "Code is properly linked to encounter $COPD_CODE_ENCOUNTER"
    fi
fi

# Check if this is a new code (added during task)
NEW_CODE_ADDED="false"
if [ "$CURRENT_COPD_COUNT" -gt "$INITIAL_COPD_COUNT" ]; then
    NEW_CODE_ADDED="true"
    echo "New COPD code was added during task"
fi

# Validate the code value is acceptable
CODE_VALUE_VALID="false"
if [ -n "$COPD_CODE_VALUE" ]; then
    case "$COPD_CODE_VALUE" in
        J44|J44.0|J44.1|J44.9)
            CODE_VALUE_VALID="true"
            echo "Code $COPD_CODE_VALUE is valid for COPD"
            ;;
        *)
            # Check if it starts with J44
            if echo "$COPD_CODE_VALUE" | grep -q "^J44"; then
                CODE_VALUE_VALID="true"
                echo "Code $COPD_CODE_VALUE is valid (J44.x pattern)"
            else
                echo "Code $COPD_CODE_VALUE may not be valid for COPD"
            fi
            ;;
    esac
fi

# Escape special characters for JSON
COPD_CODE_TEXT_ESCAPED=$(echo "$COPD_CODE_TEXT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/encounter_dx_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "target_encounter": "$TARGET_ENCOUNTER",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_dx_count": ${INITIAL_DX_COUNT:-0},
    "current_dx_count": ${CURRENT_DX_COUNT:-0},
    "initial_copd_count": ${INITIAL_COPD_COUNT:-0},
    "current_copd_count": ${CURRENT_COPD_COUNT:-0},
    "copd_code_found": $COPD_CODE_FOUND,
    "new_code_added": $NEW_CODE_ADDED,
    "diagnosis": {
        "id": "$COPD_CODE_ID",
        "encounter": "$COPD_CODE_ENCOUNTER",
        "code": "$COPD_CODE_VALUE",
        "code_text": "$COPD_CODE_TEXT_ESCAPED",
        "active": "$COPD_CODE_ACTIVE"
    },
    "validation": {
        "code_linked_to_encounter": $CODE_LINKED_TO_ENCOUNTER,
        "code_value_valid": $CODE_VALUE_VALID,
        "new_code_added": $NEW_CODE_ADDED
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result to standard location
rm -f /tmp/encounter_diagnosis_result.json 2>/dev/null || sudo rm -f /tmp/encounter_diagnosis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/encounter_diagnosis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/encounter_diagnosis_result.json
chmod 666 /tmp/encounter_diagnosis_result.json 2>/dev/null || sudo chmod 666 /tmp/encounter_diagnosis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/encounter_diagnosis_result.json"
cat /tmp/encounter_diagnosis_result.json

echo ""
echo "=== Export Complete ==="