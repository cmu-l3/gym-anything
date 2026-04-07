#!/bin/bash
echo "=== Exporting database_backup_verify result ==="

# Timestamp handling
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

BACKUP_DIR="/home/ga/MedinTux_Backups"
DATABASES=("DrTuxTest" "MedicaTuxTest" "CIM10Test" "CCAMTest")

# Prepare JSON construction
TEMP_JSON=$(mktemp /tmp/db_result.XXXXXX.json)

# Start JSON object
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"databases\": {" >> "$TEMP_JSON"

# Iterate through databases to gather stats
FIRST_DB=true
for DB in "${DATABASES[@]}"; do
    if [ "$FIRST_DB" = true ]; then FIRST_DB=false; else echo "," >> "$TEMP_JSON"; fi
    
    echo "    \"$DB\": {" >> "$TEMP_JSON"
    
    # 1. Backup File Stats
    BACKUP_FILE="$BACKUP_DIR/${DB}_backup.sql"
    if [ -f "$BACKUP_FILE" ]; then
        SIZE=$(stat -c%s "$BACKUP_FILE")
        MTIME=$(stat -c%Y "$BACKUP_FILE")
        # Check if file has SQL content (simple grep)
        if grep -qE "CREATE TABLE|INSERT INTO" "$BACKUP_FILE" 2>/dev/null; then
            VALID_SQL="true"
        else
            VALID_SQL="false"
        fi
        echo "      \"backup_exists\": true," >> "$TEMP_JSON"
        echo "      \"backup_size\": $SIZE," >> "$TEMP_JSON"
        echo "      \"backup_mtime\": $MTIME," >> "$TEMP_JSON"
        echo "      \"backup_valid_sql\": $VALID_SQL," >> "$TEMP_JSON"
    else
        echo "      \"backup_exists\": false," >> "$TEMP_JSON"
        echo "      \"backup_size\": 0," >> "$TEMP_JSON"
        echo "      \"backup_mtime\": 0," >> "$TEMP_JSON"
        echo "      \"backup_valid_sql\": false," >> "$TEMP_JSON"
    fi

    # 2. Original Database Stats
    ORIG_TABLES=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB'" 2>/dev/null || echo 0)
    ORIG_ROWS=$(mysql -u root -N -e "SELECT SUM(TABLE_ROWS) FROM information_schema.tables WHERE table_schema='$DB'" 2>/dev/null || echo 0)
    # Handle NULL row counts
    if [ "$ORIG_ROWS" == "NULL" ]; then ORIG_ROWS=0; fi
    
    echo "      \"orig_tables\": $ORIG_TABLES," >> "$TEMP_JSON"
    echo "      \"orig_rows\": $ORIG_ROWS," >> "$TEMP_JSON"

    # 3. Verification Database Stats
    VERIFY_DB="${DB}_verify"
    VERIFY_EXISTS=$(mysql -u root -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$VERIFY_DB'" 2>/dev/null || echo "")
    
    if [ -n "$VERIFY_EXISTS" ]; then
        VERIFY_TABLES=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$VERIFY_DB'" 2>/dev/null || echo 0)
        VERIFY_ROWS=$(mysql -u root -N -e "SELECT SUM(TABLE_ROWS) FROM information_schema.tables WHERE table_schema='$VERIFY_DB'" 2>/dev/null || echo 0)
        if [ "$VERIFY_ROWS" == "NULL" ]; then VERIFY_ROWS=0; fi
        
        echo "      \"verify_exists\": true," >> "$TEMP_JSON"
        echo "      \"verify_tables\": $VERIFY_TABLES," >> "$TEMP_JSON"
        echo "      \"verify_rows\": $VERIFY_ROWS" >> "$TEMP_JSON"
    else
        echo "      \"verify_exists\": false," >> "$TEMP_JSON"
        echo "      \"verify_tables\": 0," >> "$TEMP_JSON"
        echo "      \"verify_rows\": 0" >> "$TEMP_JSON"
    fi

    echo "    }" >> "$TEMP_JSON"
done
echo "  }," >> "$TEMP_JSON"

# Specific check for DrTuxTest patient count (IndexNomPrenom)
# This is a critical table for patient identity
PATIENT_COUNT_ORIG=$(mysql -u root -N -e "SELECT COUNT(*) FROM DrTuxTest.IndexNomPrenom" 2>/dev/null || echo 0)
PATIENT_COUNT_VERIFY=$(mysql -u root -N -e "SELECT COUNT(*) FROM DrTuxTest_verify.IndexNomPrenom" 2>/dev/null || echo 0)

echo "  \"specific_checks\": {" >> "$TEMP_JSON"
echo "    \"patient_count_orig\": $PATIENT_COUNT_ORIG," >> "$TEMP_JSON"
echo "    \"patient_count_verify\": $PATIENT_COUNT_VERIFY" >> "$TEMP_JSON"
echo "  }," >> "$TEMP_JSON"

# Report file verification
REPORT_FILE="$BACKUP_DIR/backup_report.txt"
if [ -f "$REPORT_FILE" ]; then
    echo "  \"report_exists\": true," >> "$TEMP_JSON"
    # Read content safely into JSON string (escaping quotes and newlines)
    # Using python for safe escaping
    CONTENT_JSON=$(python3 -c "import json; print(json.dumps(open('$REPORT_FILE').read()))" 2>/dev/null || echo "\"\"")
    echo "  \"report_content\": $CONTENT_JSON" >> "$TEMP_JSON"
else
    echo "  \"report_exists\": false," >> "$TEMP_JSON"
    echo "  \"report_content\": \"\"" >> "$TEMP_JSON"
fi

# End JSON
echo "}" >> "$TEMP_JSON"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json