#!/bin/bash
echo "=== Exporting Create View Result ==="

source /workspace/scripts/task_utils.sh

# 1. Basic File Stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 2. Extract View Definition from ODB
# LibreOffice Base ODB files are ZIPs containing a 'database/script' file with the HSQLDB DDL.
VIEW_FOUND="false"
VIEW_DEFINITION=""
EXTRACT_DIR="/tmp/odb_extract_$(date +%s)"
mkdir -p "$EXTRACT_DIR"

if [ -f "$ODB_PATH" ]; then
    echo "Extracting ODB file..."
    if unzip -q "$ODB_PATH" "database/script" -d "$EXTRACT_DIR" 2>/dev/null; then
        SCRIPT_FILE="$EXTRACT_DIR/database/script"
        
        # Look for the view definition. HSQLDB 1.8 usually writes:
        # CREATE SCHEMA PUBLIC ...
        # CREATE USER ...
        # CREATE VIEW "ViewName" AS SELECT ...
        
        # Grep for the specific view name (case insensitive)
        if grep -qi "CREATE VIEW.*CustomerPurchaseSummary" "$SCRIPT_FILE"; then
            VIEW_FOUND="true"
            # Extract the line containing the view definition
            VIEW_DEFINITION=$(grep -i "CREATE VIEW.*CustomerPurchaseSummary" "$SCRIPT_FILE" | head -1)
        fi
    else
        echo "Failed to unzip ODB file."
    fi
fi

# 3. Clean up extraction
rm -rf "$EXTRACT_DIR"

# 4. Check if App is Running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_exists": true,
    "odb_modified_during_task": $ODB_MODIFIED,
    "view_found": $VIEW_FOUND,
    "view_definition": $(echo "$VIEW_DEFINITION" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="