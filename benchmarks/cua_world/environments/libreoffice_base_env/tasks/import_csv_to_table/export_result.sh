#!/bin/bash
echo "=== Exporting import_csv_to_table result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Close LibreOffice to flush changes to disk
kill_libreoffice

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Analyze the ODB file
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_ROWS=$(cat /tmp/expected_row_count.txt 2>/dev/null || echo "0")
ODB_MODIFIED="false"
TABLE_FOUND="false"
INSERT_COUNT=0
COLUMNS_DETECTED=0

if [ -f "$ODB_PATH" ]; then
    # Check timestamp
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi

    # Extract database script
    # ODB is a zip file. The HSQLDB data is in database/script
    mkdir -p /tmp/odb_extract
    unzip -q -o "$ODB_PATH" "database/script" -d /tmp/odb_extract 2>/dev/null || true
    
    SCRIPT_FILE="/tmp/odb_extract/database/script"
    
    if [ -f "$SCRIPT_FILE" ]; then
        echo " analyzing database script..."
        
        # Check for CREATE TABLE "RockLongTracks" (case insensitive)
        if grep -iq 'CREATE TABLE.*"RockLongTracks"' "$SCRIPT_FILE"; then
            TABLE_FOUND="true"
            
            # Count columns in the CREATE statement (rough heuristic: count commas + 1)
            # Find the line, remove quoted identifiers to avoid confusion, count commas
            CREATE_LINE=$(grep -i 'CREATE TABLE.*"RockLongTracks"' "$SCRIPT_FILE" | head -1)
            # Rough column count
            COLUMNS_DETECTED=$(echo "$CREATE_LINE" | tr -cd ',' | wc -c)
            COLUMNS_DETECTED=$((COLUMNS_DETECTED + 1))
        fi
        
        # Count INSERTS into this table
        # HSQLDB script format: INSERT INTO "RockLongTracks" VALUES(...)
        INSERT_COUNT=$(grep -i 'INSERT INTO.*"RockLongTracks"' "$SCRIPT_FILE" | wc -l)
        
        # Verify original tables are still there (sanity check)
        ORIGINAL_TABLES_COUNT=$(grep -c "CREATE TABLE" "$SCRIPT_FILE")
    fi
fi

# 4. Check trajectory for evidence (screenshots taken by agent)
TRAJECTORY_SCREENSHOTS=$(find /home/ga -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_modified": $ODB_MODIFIED,
    "table_found": $TABLE_FOUND,
    "insert_count": $INSERT_COUNT,
    "expected_rows": $EXPECTED_ROWS,
    "columns_detected": $COLUMNS_DETECTED,
    "original_tables_count": ${ORIGINAL_TABLES_COUNT:-0},
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="