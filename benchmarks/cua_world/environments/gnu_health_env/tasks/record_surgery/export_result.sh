#!/bin/bash
echo "=== Exporting record_surgery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/surgery_final_state.png

# Load baselines
BASELINE_SURGERY_MAX=$(cat /tmp/surgery_baseline_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/surgery_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/surgery_task_start_date 2>/dev/null || date -Iseconds)

echo "Target patient_id: $TARGET_PATIENT_ID"
echo "Baseline Surgery Max ID: $BASELINE_SURGERY_MAX"

# --- 1. Find New Surgeries for Target Patient ---
# Handle possible missing notes column gracefully by using COALESCE
SURGERY_DATA=$(gnuhealth_db_query "
    SELECT 
        id,
        COALESCE(description, ''),
        COALESCE(surgery_date::date::text, ''),
        COALESCE(classification, ''),
        REPLACE(COALESCE(extra_info, ''), E'\n', ' ')
    FROM gnuhealth_surgery
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_SURGERY_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

SURGERY_FOUND="false"
SURG_ID=""
SURG_DESC=""
SURG_DATE=""
SURG_CLASS=""
SURG_NOTES=""

if [ -n "$SURGERY_DATA" ]; then
    SURGERY_FOUND="true"
    # Using awk to split by pipe since psql -At uses | as delimiter
    SURG_ID=$(echo "$SURGERY_DATA" | awk -F'|' '{print $1}')
    SURG_DESC=$(echo "$SURGERY_DATA" | awk -F'|' '{print $2}')
    SURG_DATE=$(echo "$SURGERY_DATA" | awk -F'|' '{print $3}')
    SURG_CLASS=$(echo "$SURGERY_DATA" | awk -F'|' '{print $4}')
    SURG_NOTES=$(echo "$SURGERY_DATA" | awk -F'|' '{print $5}')
fi

# --- 2. Check for ANY new surgery regardless of patient (for partial credit detection) ---
ANY_NEW_SURGERY=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_surgery
    WHERE id > $BASELINE_SURGERY_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "Surgery found for Ana: $SURGERY_FOUND (ID: $SURG_ID)"
echo "Total new surgeries: ${ANY_NEW_SURGERY:-0}"

# Escape special characters for JSON output
SURG_DESC_ESC=$(json_escape "$SURG_DESC")
SURG_CLASS_ESC=$(json_escape "$SURG_CLASS")
SURG_NOTES_ESC=$(json_escape "$SURG_NOTES")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/surgery_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "surgery_found": $SURGERY_FOUND,
    "any_new_surgery_count": ${ANY_NEW_SURGERY:-0},
    "surgery": {
        "id": "$SURG_ID",
        "description": "$SURG_DESC_ESC",
        "date": "$SURG_DATE",
        "classification": "$SURG_CLASS_ESC",
        "notes": "$SURG_NOTES_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result /tmp/record_surgery_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/record_surgery_result.json
echo "=== Export Complete ==="