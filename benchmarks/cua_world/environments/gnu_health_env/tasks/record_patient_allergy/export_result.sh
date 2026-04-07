#!/bin/bash
echo "=== Exporting Record Patient Allergy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TARGET_PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "0")
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count.txt 2>/dev/null || echo "0")

# Current allergy count
CURRENT_ALLERGY_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE name = $TARGET_PATIENT_ID AND is_allergy = true
" | tr -d '[:space:]')

# Get the newly created allergy data if it exists
ALLERGY_DATA=$(gnuhealth_db_query "
    SELECT gpd.allergy_type, gpd.disease_severity, gp.code, gp.name
    FROM gnuhealth_patient_disease gpd
    LEFT JOIN gnuhealth_pathology gp ON gpd.pathology = gp.id
    WHERE gpd.name = $TARGET_PATIENT_ID
      AND gpd.is_allergy = true
    ORDER BY gpd.id DESC LIMIT 1
" 2>/dev/null)

ALLERGY_TYPE=""
SEVERITY=""
PATHOLOGY_CODE=""
PATHOLOGY_NAME=""

if [ -n "$ALLERGY_DATA" ]; then
    ALLERGY_TYPE=$(echo "$ALLERGY_DATA" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    SEVERITY=$(echo "$ALLERGY_DATA" | awk -F'|' '{print $2}' | tr -d '[:space:]')
    PATHOLOGY_CODE=$(echo "$ALLERGY_DATA" | awk -F'|' '{print $3}' | tr -d '[:space:]')
    PATHOLOGY_NAME=$(echo "$ALLERGY_DATA" | awk -F'|' '{print $4}' | xargs)
fi

# Determine if a record was newly created based on count (anti-gaming check)
NEWLY_CREATED="false"
if [ "${CURRENT_ALLERGY_COUNT:-0}" -gt "${INITIAL_ALLERGY_COUNT:-0}" ]; then
    NEWLY_CREATED="true"
fi

# Escape JSON strings
PATHOLOGY_NAME_ESC=$(echo "$PATHOLOGY_NAME" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/allergy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_allergy_count": ${INITIAL_ALLERGY_COUNT:-0},
    "current_allergy_count": ${CURRENT_ALLERGY_COUNT:-0},
    "newly_created": $NEWLY_CREATED,
    "allergy_type": "$ALLERGY_TYPE",
    "severity": "$SEVERITY",
    "pathology_code": "$PATHOLOGY_CODE",
    "pathology_name": "$PATHOLOGY_NAME_ESC",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="