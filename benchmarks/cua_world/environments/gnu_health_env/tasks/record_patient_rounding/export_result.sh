#!/bin/bash
echo "=== Exporting record_patient_rounding result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/rounding_final_state.png

# Load baselines
BASELINE_ROUNDING_MAX=$(cat /tmp/rounding_baseline_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/rounding_target_patient_id 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"
echo "Baseline Rounding MAX: $BASELINE_ROUNDING_MAX"

# --- Fetch the latest rounding record for the target patient created after baseline ---
ROUNDING_RECORD=$(gnuhealth_db_query "
    SELECT 
        r.id, 
        COALESCE(r.temperature::text, 'null'), 
        COALESCE(r.systolic::text, 'null'), 
        COALESCE(r.diastolic::text, 'null'), 
        COALESCE(r.bpm::text, 'null'), 
        COALESCE(r.respiratory_rate::text, 'null'), 
        COALESCE(r.osat::text, 'null'), 
        COALESCE(r.glycemia::text, 'null'), 
        COALESCE(r.gcs_eyes::text, 'null'), 
        COALESCE(r.gcs_verbal::text, 'null'), 
        COALESCE(r.gcs_motor::text, 'null'), 
        COALESCE(r.pain::text, 'null')
    FROM gnuhealth_patient_rounding r
    JOIN gnuhealth_inpatient_registration ir ON r.name = ir.id
    WHERE ir.patient = $TARGET_PATIENT_ID
      AND r.id > $BASELINE_ROUNDING_MAX
    ORDER BY r.id DESC 
    LIMIT 1" 2>/dev/null | head -1)

RECORD_FOUND="false"
R_ID="null"
R_TEMP="null"
R_SYS="null"
R_DIA="null"
R_BPM="null"
R_RR="null"
R_OSAT="null"
R_GLY="null"
R_GCS_E="null"
R_GCS_V="null"
R_GCS_M="null"
R_PAIN="null"

if [ -n "$ROUNDING_RECORD" ]; then
    RECORD_FOUND="true"
    # Parse the | separated string
    R_ID=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    R_TEMP=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    R_SYS=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    R_DIA=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    R_BPM=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
    R_RR=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $6}' | tr -d ' ')
    R_OSAT=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $7}' | tr -d ' ')
    R_GLY=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $8}' | tr -d ' ')
    R_GCS_E=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $9}' | tr -d ' ')
    R_GCS_V=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $10}' | tr -d ' ')
    R_GCS_M=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $11}' | tr -d ' ')
    R_PAIN=$(echo "$ROUNDING_RECORD" | awk -F'|' '{print $12}' | tr -d ' ')
fi

# Check for ANY newly created rounding record (to catch if agent linked it to the wrong patient)
ANY_NEW_ROUNDING=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_rounding 
    WHERE id > $BASELINE_ROUNDING_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "Record found for Ana: $RECORD_FOUND (ID: $R_ID)"
echo "Any new rounding records created: ${ANY_NEW_ROUNDING:-0}"

# Create JSON output
TEMP_JSON=$(mktemp /tmp/record_patient_rounding_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "Ana Isabel Betz",
    "record_found": $RECORD_FOUND,
    "any_new_record_count": ${ANY_NEW_ROUNDING:-0},
    "vitals": {
        "temperature": "$R_TEMP",
        "systolic": "$R_SYS",
        "diastolic": "$R_DIA",
        "bpm": "$R_BPM",
        "respiratory_rate": "$R_RR",
        "osat": "$R_OSAT",
        "glycemia": "$R_GLY",
        "gcs_eyes": "$R_GCS_E",
        "gcs_verbal": "$R_GCS_V",
        "gcs_motor": "$R_GCS_M",
        "pain": "$R_PAIN"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/record_patient_rounding_result.json 2>/dev/null || sudo rm -f /tmp/record_patient_rounding_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_patient_rounding_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_patient_rounding_result.json
chmod 666 /tmp/record_patient_rounding_result.json 2>/dev/null || sudo chmod 666 /tmp/record_patient_rounding_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/record_patient_rounding_result.json"
cat /tmp/record_patient_rounding_result.json
echo "=== Export Complete ==="