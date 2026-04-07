#!/bin/bash
echo "=== Exporting EMR Transcription Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Subject CV-106 Lookup
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
CV106_DATA=$(oc_query "SELECT ss.study_subject_id, sb.gender, sb.date_of_birth FROM study_subject ss JOIN subject sb ON ss.subject_id = sb.subject_id WHERE ss.label = 'CV-106' AND ss.study_id = $CV_STUDY_ID AND ss.status_id != 3 LIMIT 1")

CV106_FOUND="false"
CV106_SS_ID=""
CV106_GENDER=""
CV106_DOB=""

if [ -n "$CV106_DATA" ]; then
    CV106_FOUND="true"
    CV106_SS_ID=$(echo "$CV106_DATA" | cut -d'|' -f1)
    CV106_GENDER=$(echo "$CV106_DATA" | cut -d'|' -f2)
    CV106_DOB=$(echo "$CV106_DATA" | cut -d'|' -f3)
fi

# 2. Event Date Lookup
EVENT_DATE=""
if [ -n "$CV106_SS_ID" ]; then
    EVENT_DATE=$(oc_query "SELECT se.start_date FROM study_event se WHERE se.study_subject_id = $CV106_SS_ID ORDER BY se.study_event_id DESC LIMIT 1")
fi

# 3. Item Data Lookup
ITEM_VALUES=""
if [ -n "$CV106_SS_ID" ]; then
    ITEM_VALUES=$(oc_query "SELECT string_agg(value, ', ') FROM item_data id JOIN event_crf ec ON id.event_crf_id = ec.event_crf_id WHERE ec.study_subject_id = $CV106_SS_ID AND id.value IS NOT NULL AND id.value != ''")
fi

# 4. Discrepancy Notes Lookup (Grab all recent notes globally to be robust against where they attached it)
NOTES=$(oc_query "SELECT string_agg(description || ' ' || detailed_notes, ' | ') FROM discrepancy_note WHERE date_created >= (NOW() - INTERVAL '1 day')")

# Create JSON Export
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "cv106_found": $CV106_FOUND,
    "cv106_gender": "$(json_escape "${CV106_GENDER}")",
    "cv106_dob": "$(json_escape "${CV106_DOB}")",
    "event_date": "$(json_escape "${EVENT_DATE}")",
    "item_values": "$(json_escape "${ITEM_VALUES}")",
    "discrepancy_notes": "$(json_escape "${NOTES}")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
cp "$TEMP_JSON" /tmp/emr_task_result.json
chmod 666 /tmp/emr_task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="