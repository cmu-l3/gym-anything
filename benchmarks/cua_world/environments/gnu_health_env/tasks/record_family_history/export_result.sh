#!/bin/bash
echo "=== Exporting record_family_history result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot to document the end state
take_screenshot /tmp/task_final.png

# Load baselines and target info
ANA_ID=$(cat /tmp/target_patient_id 2>/dev/null || echo "0")
TABLE_NAME=$(cat /tmp/family_disease_table 2>/dev/null || echo "gnuhealth_family_disease")
BASELINE_MAX=$(cat /tmp/baseline_max_id 2>/dev/null || echo "0")

# Fetch Pathology IDs for the required ICD-10 codes
I25_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code='I25' LIMIT 1" | tr -d '[:space:]')
E11_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code='E11' LIMIT 1" | tr -d '[:space:]')
M32_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code='M32' LIMIT 1" | tr -d '[:space:]')

# Query the database for records created during the task for the target patient
# We output the raw rows as JSON text to cleanly parse both foreign keys and text fields
ROWS_JSON=$(gnuhealth_db_query "SELECT row_to_json(t)::text FROM (SELECT * FROM $TABLE_NAME WHERE patient = $ANA_ID AND id > $BASELINE_MAX) t" 2>/dev/null)

# Verify presence of the specific diseases by checking if their IDs exist in the exported JSON rows
HAS_I25="false"
HAS_E11="false"
HAS_M32="false"

if [ -n "$I25_ID" ] && echo "$ROWS_JSON" | grep -qE "(:$I25_ID,|: $I25_ID,|:$I25_ID\}|: $I25_ID\})"; then HAS_I25="true"; fi
if [ -n "$E11_ID" ] && echo "$ROWS_JSON" | grep -qE "(:$E11_ID,|: $E11_ID,|:$E11_ID\}|: $E11_ID\})"; then HAS_E11="true"; fi
if [ -n "$M32_ID" ] && echo "$ROWS_JSON" | grep -qE "(:$M32_ID,|: $M32_ID,|:$M32_ID\}|: $M32_ID\})"; then HAS_M32="true"; fi

# Verify presence of the relative descriptions
HAS_FATHER="false"
HAS_MOTHER="false"
HAS_SISTER="false"

if echo "$ROWS_JSON" | grep -qiE "father|paternal"; then HAS_FATHER="true"; fi
if echo "$ROWS_JSON" | grep -qiE "mother|maternal"; then HAS_MOTHER="true"; fi
if echo "$ROWS_JSON" | grep -qiE "sister|sibling"; then HAS_SISTER="true"; fi

# Get the delta of how many entries were actually added
NEW_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE patient = $ANA_ID AND id > $BASELINE_MAX" | tr -d '[:space:]')

# Save results to a temporary JSON file to avoid permission issues, then safely move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "has_i25": $HAS_I25,
    "has_e11": $HAS_E11,
    "has_m32": $HAS_M32,
    "has_father_relative": $HAS_FATHER,
    "has_mother_relative": $HAS_MOTHER,
    "has_sister_relative": $HAS_SISTER,
    "new_records_count": ${NEW_COUNT:-0},
    "target_patient_id": "$ANA_ID",
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

safe_write_result /tmp/task_result.json "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="