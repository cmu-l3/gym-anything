#!/bin/bash
# Export script for Regionalized Location Tagging task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Regionalized Location Tagging Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check CSV Output
CSV_PATH="/home/ga/LCA_Results/location_mapping.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING="false"
CSV_CONTENT_HEAD=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    FILE_MTIME=$(stat -c %Y "$CSV_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    
    # Read first few lines for verification
    CSV_CONTENT_HEAD=$(head -n 5 "$CSV_PATH" | base64 -w 0)
fi

# 4. Query OpenLCA Database (Derby)
# We need to find the database the agent used.
# It's likely the largest one or one with USLCI in the name.

DB_DIR="/home/ga/openLCA-data-1.4/databases"
TARGET_DB=""
MAX_SIZE=0

# Find the most likely active database
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    # Size check
    SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1)
    if [ "$SIZE" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="$SIZE"
        TARGET_DB="$db_path"
    fi
    # Name priority
    db_name=$(basename "$db_path")
    if echo "$db_name" | grep -qi "uslci\|lci"; then
        TARGET_DB="$db_path"
        break
    fi
done

LOCATIONS_FOUND="[]"
PROCESS_ASSIGNMENTS="[]"
DB_NAME=""

if [ -n "$TARGET_DB" ]; then
    DB_NAME=$(basename "$TARGET_DB")
    echo "Querying database: $DB_NAME"

    # Close OpenLCA to ensure DB access (Derby embedded lock)
    close_openlca
    sleep 3

    # QUERY 1: Check for the 3 locations
    # TBL_LOCATIONS: ID, NAME, CODE, LATITUDE, LONGITUDE...
    LOC_QUERY="SELECT CODE, NAME, LATITUDE, LONGITUDE FROM TBL_LOCATIONS WHERE CODE IN ('US-CA', 'US-TX', 'US-OH')"
    
    # Run query using helper
    LOC_RESULT=$(derby_query "$TARGET_DB" "$LOC_QUERY")
    
    # Parse result into JSON array (simple parsing)
    # Derby output is formatted text. We'll capture it raw and parse in python verifier if needed, 
    # or do basic bash parsing here.
    # Let's save the raw output to the JSON.
    LOCATIONS_RAW=$(echo "$LOC_RESULT" | grep -v "^ij>" | base64 -w 0)

    # QUERY 2: Check for process assignments
    # TBL_PROCESSES: ID, NAME, F_LOCATION ...
    # Join with Locations
    ASSIGN_QUERY="SELECT p.NAME, l.CODE FROM TBL_PROCESSES p JOIN TBL_LOCATIONS l ON p.F_LOCATION = l.ID WHERE l.CODE IN ('US-CA', 'US-TX', 'US-OH')"
    
    ASSIGN_RESULT=$(derby_query "$TARGET_DB" "$ASSIGN_QUERY")
    ASSIGNMENTS_RAW=$(echo "$ASSIGN_RESULT" | grep -v "^ij>" | base64 -w 0)
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "csv_head_b64": "$CSV_CONTENT_HEAD",
    "db_found": "$DB_NAME",
    "locations_query_b64": "$LOCATIONS_RAW",
    "assignments_query_b64": "$ASSIGNMENTS_RAW",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
export_json_result "/tmp/task_result.json" < "$TEMP_JSON"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"