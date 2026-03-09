#!/bin/bash
echo "=== Exporting generate_marketing_list results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file details
CSV_PATH="/home/ga/Documents/mailing_list.csv"
CSV_EXISTS="false"
CSV_CONTENT=""
CSV_SIZE="0"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape for JSON)
    # limit to first 100 lines to avoid massive JSON
    CSV_CONTENT=$(head -n 100 "$CSV_PATH" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
fi

# 3. Check for Database Persistence (Table Creation)
# Extract the script file from the ODB zip to look for the CREATE TABLE statement
ODB_PATH="/home/ga/chinook.odb"
ODB_SCRIPT_CONTENT=""
TABLE_PERSISTED="false"

if [ -f "$ODB_PATH" ]; then
    # Create temp dir for extraction
    mkdir -p /tmp/odb_check
    # Unzip specifically the database/script file
    unzip -p "$ODB_PATH" database/script > /tmp/odb_check/script 2>/dev/null || true
    
    if [ -f "/tmp/odb_check/script" ]; then
        # Check for table creation (case insensitive)
        if grep -qi "CREATE TABLE.*TargetedMailingList" /tmp/odb_check/script; then
            TABLE_PERSISTED="true"
        fi
        # Also check for INSERT INTO statements for this table
        ROWS_INSERTED=$(grep -ci "INSERT INTO.*TargetedMailingList" /tmp/odb_check/script || echo "0")
    fi
    rm -rf /tmp/odb_check
fi

# 4. Generate Ground Truth using Python and the source SQLite file
# We calculate the expected list of CustomerIDs and formatted strings locally
# to compare against what the agent produced.
GROUND_TRUTH_JSON=$(python3 -c "
import sqlite3
import json
import os

try:
    conn = sqlite3.connect('/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
    cursor = conn.cursor()
    
    # Query: Customers who bought Jazz or Blues
    query = '''
        SELECT DISTINCT 
            c.CustomerId, 
            c.LastName || ', ' || c.FirstName as FormalName,
            c.Address, c.City, c.State, c.PostalCode, c.Country
        FROM Customer c
        JOIN Invoice i ON c.CustomerId = i.CustomerId
        JOIN InvoiceLine il ON i.InvoiceId = il.InvoiceId
        JOIN Track t ON il.TrackId = t.TrackId
        JOIN Genre g ON t.GenreId = g.GenreId
        WHERE g.Name IN ('Jazz', 'Blues')
        ORDER BY c.CustomerId
    '''
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    expected_data = []
    for r in rows:
        cid, formal_name, addr, city, state, zip_code, country = r
        
        # Replicate expected formatting logic for FullAddress
        # \"Address, City, State ZipCode, Country\"
        # Handle NULL State
        
        state_str = state if state else ''
        # Agent might produce double spaces if they just concat, or handle it cleanly.
        # We will check if the agent's string *contains* the key parts.
        
        expected_data.append({
            'CustomerId': cid,
            'FormalName': formal_name,
            'Parts': {
                'Address': addr,
                'City': city,
                'State': state,
                'Zip': zip_code,
                'Country': country
            }
        })
        
    print(json.dumps(expected_data))
    conn.close()
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# 5. Build Final JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_content_json": $CSV_CONTENT,
    "table_persisted": $TABLE_PERSISTED,
    "rows_persisted_count": ${ROWS_INSERTED:-0},
    "ground_truth": $GROUND_TRUTH_JSON
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="