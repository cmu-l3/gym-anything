#!/bin/bash
echo "=== Exporting link_diagnosis_to_patient result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || echo "1970-01-01 00:00:00")

# ============================================================
# 1. Capture Final State
# ============================================================
# Take final screenshot
take_screenshot /tmp/task_final.png
sleep 1

# Check output file
OUTPUT_FILE="/home/ga/diagnosis_result.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | base64 -w 0)
    
    # Check modification time
    F_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# ============================================================
# 2. Query Database for Diagnosis
# ============================================================
# We need to find if "I10" was added to DUBOIS Marie's records
# MedinTux stores clinical notes/codes in tables like Rubriques, RubriquesHead, or specific Terrain tables.
# We will search the 'Rubriques' (Observations/Notes) table for the code I10 associated with the patient.

# Get Patient GUID
GUID=$(get_patient_guid "DUBOIS" "Marie")
echo "Patient GUID: $GUID"

DB_MATCH="false"
DB_RECORD=""

if [ -n "$GUID" ]; then
    # Search for I10 in Rubriques text blob for this patient
    # We look for records created/modified recently if possible, or just existence since we wiped it in setup
    
    QUERY="SELECT Rbq_Date, Rbq_NomDos, Rbq_Texte FROM Rubriques \
           WHERE Rbq_IDDos='$GUID' AND (Rbq_Texte LIKE '%I10%' OR Rbq_Texte LIKE '%Hypertension%')"
           
    # Run query
    RESULT=$(mysql -u root DrTuxTest -B -e "$QUERY" 2>/dev/null)
    
    if [ -n "$RESULT" ]; then
        DB_MATCH="true"
        DB_RECORD=$(echo "$RESULT" | base64 -w 0)
        echo "Found diagnosis record in database."
    else
        echo "No diagnosis record found in Rubriques."
    fi
fi

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_fresh": $FILE_CREATED_DURING,
    "output_content_b64": "$OUTPUT_CONTENT",
    "db_record_found": $DB_MATCH,
    "db_record_b64": "$DB_RECORD",
    "patient_guid": "$GUID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"