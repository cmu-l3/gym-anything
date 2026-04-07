#!/bin/bash
echo "=== Exporting Create Medical Correspondent Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if MedinTux is still running
APP_RUNNING=$(pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# Query the database for the new record
# We look for MARTIN Sophie in the Personnes table
echo "Querying database for MARTIN Sophie..."

# Use a temporary file for the SQL result to handle potential special chars safely
SQL_RESULT_FILE=$(mktemp)

mysql -u root DrTuxTest -N -e "SELECT ID_PrimKey, Nom, Prenom, Ville, CodePostal, Tel1, Tel2, Mobile, Qualite, Adresse FROM Personnes WHERE Nom='MARTIN' AND Prenom='Sophie' ORDER BY ID_PrimKey DESC LIMIT 1" > "$SQL_RESULT_FILE" 2>/dev/null || true

# Check if we found a record
if [ -s "$SQL_RESULT_FILE" ]; then
    RECORD_FOUND="true"
    # Read fields into variables (tab-separated)
    # ID, Nom, Prenom, Ville, CP, Tel1, Tel2, Mobile, Qualite, Adresse
    read -r DB_ID DB_NOM DB_PRENOM DB_VILLE DB_CP DB_TEL1 DB_TEL2 DB_MOBILE DB_QUALITE DB_ADRESSE < "$SQL_RESULT_FILE"
else
    RECORD_FOUND="false"
    DB_ID=""
    DB_NOM=""
    DB_PRENOM=""
    DB_VILLE=""
    DB_CP=""
    DB_TEL1=""
    DB_TEL2=""
    DB_MOBILE=""
    DB_QUALITE=""
    DB_ADRESSE=""
fi
rm -f "$SQL_RESULT_FILE"

# Calculate count change
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM Personnes" 2>/dev/null || echo "0")
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "record_found": $RECORD_FOUND,
    "db_record": {
        "id": "$DB_ID",
        "nom": "$DB_NOM",
        "prenom": "$DB_PRENOM",
        "ville": "$DB_VILLE",
        "cp": "$DB_CP",
        "tel1": "$DB_TEL1",
        "tel2": "$DB_TEL2",
        "mobile": "$DB_MOBILE",
        "qualite": "$DB_QUALITE",
        "adresse": "$DB_ADRESSE"
    },
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_diff": $COUNT_DIFF,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="