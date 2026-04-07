#!/bin/bash
echo "=== Exporting create_patient_view results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database connection details
DB_USER="root"
DB_NAME="DrTuxTest"
VIEW_NAME="vue_patients_complete"

# 1. Check if View Exists
VIEW_EXISTS_CHECK=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$VIEW_NAME'" 2>/dev/null || echo "0")
if [ "$VIEW_EXISTS_CHECK" -gt "0" ]; then
    VIEW_EXISTS="true"
else
    VIEW_EXISTS="false"
fi

# 2. Get View Definition (Create Statement)
CREATE_STATEMENT=""
if [ "$VIEW_EXISTS" = "true" ]; then
    # Use python to safely capture the create statement potentially containing quotes
    CREATE_STATEMENT=$(mysql -u $DB_USER $DB_NAME -N -e "SHOW CREATE VIEW $VIEW_NAME" 2>/dev/null | sed 's/\t/ /g')
fi

# 3. Get Columns List
COLUMNS_JSON="[]"
if [ "$VIEW_EXISTS" = "true" ]; then
    # Generate a JSON array of column names
    COLUMNS_LIST=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$VIEW_NAME' ORDER BY ORDINAL_POSITION")
    # Convert newline separated list to JSON array
    COLUMNS_JSON=$(echo "$COLUMNS_LIST" | jq -R . | jq -s .)
fi

# 4. Check Data Retrieval and Logic
ROW_COUNT=0
SAMPLE_DATA="[]"
AGE_CHECK_PASSED="false"
FILTER_CHECK_PASSED="false"

if [ "$VIEW_EXISTS" = "true" ]; then
    # Count rows
    ROW_COUNT=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT COUNT(*) FROM $VIEW_NAME" 2>/dev/null || echo "0")
    
    # Get sample data (first 5 rows) as JSON
    # We use a python one-liner to dump result as JSON because bash JSON creation is fragile
    SAMPLE_DATA=$(mysql -u $DB_USER $DB_NAME -e "SELECT * FROM $VIEW_NAME LIMIT 5" 2>/dev/null | \
    python3 -c 'import sys, csv, json; reader = csv.DictReader(sys.stdin, delimiter="\t"); print(json.dumps([row for row in reader]))')

    # Verify Logic: Check a specific record for age calculation if data permits
    # We insert a probe record to verify age calc logic definitively without relying on existing data
    PROBE_GUID="VERIFY-AGE-$(date +%s)"
    PROBE_DOB="2000-01-01"
    # Calculate expected age (approximate year diff)
    EXPECTED_AGE=$(mysql -u $DB_USER -N -e "SELECT TIMESTAMPDIFF(YEAR, '$PROBE_DOB', CURDATE())")
    
    # Insert probe
    mysql -u $DB_USER $DB_NAME -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$PROBE_GUID', 'PROBE', 'AgeCheck', 'Dossier')" 2>/dev/null
    mysql -u $DB_USER $DB_NAME -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_Nee) VALUES ('$PROBE_GUID', '$PROBE_DOB')" 2>/dev/null
    
    # Query the view for this probe
    ACTUAL_AGE=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT age_annees FROM $VIEW_NAME WHERE guid='$PROBE_GUID'" 2>/dev/null || echo "-1")
    
    if [ "$ACTUAL_AGE" = "$EXPECTED_AGE" ]; then
        AGE_CHECK_PASSED="true"
    fi
    
    # Verify Logic: Filter check
    # Insert a non-dossier record
    PROBE_BAD="VERIFY-BAD-$(date +%s)"
    mysql -u $DB_USER $DB_NAME -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Type) VALUES ('$PROBE_BAD', 'PROBE', 'NotDossier')" 2>/dev/null
    
    # Check if it appears in view
    BAD_COUNT=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT COUNT(*) FROM $VIEW_NAME WHERE guid='$PROBE_BAD'" 2>/dev/null || echo "0")
    if [ "$BAD_COUNT" -eq "0" ]; then
        FILTER_CHECK_PASSED="true"
    fi
    
    # Clean up probes
    mysql -u $DB_USER $DB_NAME -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$PROBE_GUID', '$PROBE_BAD')" 2>/dev/null
    mysql -u $DB_USER $DB_NAME -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss IN ('$PROBE_GUID', '$PROBE_BAD')" 2>/dev/null
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application (xterm/mysql) was running/focused is implicit by success, but we check screenshot existence
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "view_exists": $VIEW_EXISTS,
    "create_statement": $(echo "$CREATE_STATEMENT" | jq -R .),
    "columns": $COLUMNS_JSON,
    "row_count": $ROW_COUNT,
    "sample_data": $SAMPLE_DATA,
    "logic_verification": {
        "age_calculation_correct": $AGE_CHECK_PASSED,
        "filter_dossier_correct": $FILTER_CHECK_PASSED
    },
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="