#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Check if App was running
APP_WAS_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# 3. Stop Floreant POS to release Derby DB lock
# Derby in embedded mode locks the DB file. We must stop the app to query it from CLI.
kill_floreant
sleep 2

# 4. Query the Database
# We need to extract:
# - List of Virtual Printers (to find ID of 'Bar Printer')
# - Configuration of 'Beverages' category (to see its assigned printer ID)

DB_PATH="/opt/floreantpos/database/derby-server/posdb"
IJ_SCRIPT="/tmp/query_routing.sql"
DB_OUTPUT="/tmp/db_query_output.txt"

# Create SQL script
cat > "$IJ_SCRIPT" << EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT ID, NAME FROM VIRTUAL_PRINTER;
SELECT NAME, VIRTUAL_PRINTER_ID FROM MENU_CATEGORY WHERE NAME = 'Beverages' OR NAME = 'BEVERAGES';
EXIT;
EOF

# Run ij tool
echo "Querying Derby database..."
export CLASSPATH="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"

# Run query and capture output
java -Dderby.system.home=/opt/floreantpos/database \
     org.apache.derby.tools.ij "$IJ_SCRIPT" > "$DB_OUTPUT" 2>&1 || true

echo "--- DB Output Preview ---"
head -n 20 "$DB_OUTPUT"
echo "..."

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_WAS_RUNNING,
    "db_output_file": "$DB_OUTPUT",
    "timestamp": $(date +%s)
}
EOF

# Move result to expected location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="