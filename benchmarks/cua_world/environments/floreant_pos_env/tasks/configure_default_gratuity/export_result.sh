#!/bin/bash
echo "=== Exporting configure_default_gratuity result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot BEFORE killing app
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Check if App was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Terminate Floreant POS to release Derby Database lock
# CRITICAL: Embedded Derby cannot be queried while app is running
echo "Stopping Floreant POS to query database..."
kill_floreant
sleep 2

# 4. Query the Derby Database
# We need to extract DEFAULT_GRATUITY and SERVICE_CHARGE_PERCENTAGE from RESTAURANT table
DB_PATH="/opt/floreantpos/database/derby-server/posdb"
CLASSPATH="/opt/floreantpos/lib/*"

echo "Querying database at $DB_PATH..."

# Create SQL script
cat > /tmp/query_gratuity.sql <<EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT DEFAULT_GRATUITY, SERVICE_CHARGE_PERCENTAGE FROM RESTAURANT;
EXIT;
EOF

# Run query using Derby's ij tool
# Output format is typically:
# DEFAULT_GRATUITY|SERVICE_CHARGE_PERCENTAGE
# ------------------------------------------
# 18.0            |0.0
QUERY_OUTPUT=$(java -cp "$CLASSPATH" org.apache.derby.tools.ij /tmp/query_gratuity.sql 2>&1)

echo "--- Query Output ---"
echo "$QUERY_OUTPUT"
echo "--------------------"

# Extract values using simple text processing
# Look for line with numbers like "18.0            |0.0" or similar
# We grep for a line containing digits and a pipe, then try to parse
VALUES_LINE=$(echo "$QUERY_OUTPUT" | grep -E "[0-9]+\.[0-9]*.*\|.*[0-9]+\.[0-9]*" | tail -1)

# Default values if parsing fails
GRATUITY_VAL="-1.0"
SERVICE_CHARGE_VAL="-1.0"

if [ -n "$VALUES_LINE" ]; then
    # Remove whitespace
    CLEAN_LINE=$(echo "$VALUES_LINE" | tr -d '[:space:]')
    # Parse based on pipe delimiter
    GRATUITY_VAL=$(echo "$CLEAN_LINE" | cut -d'|' -f1)
    SERVICE_CHARGE_VAL=$(echo "$CLEAN_LINE" | cut -d'|' -f2)
fi

echo "Parsed Gratuity: $GRATUITY_VAL"
echo "Parsed Service Charge: $SERVICE_CHARGE_VAL"

# 5. Check persistence/modification
# Get DB modification time
DB_MODIFIED="false"
DB_FILE=$(find "$DB_PATH" -name "*.dat" -o -name "log*" | head -1)
if [ -n "$DB_FILE" ]; then
    DB_MTIME=$(stat -c %Y "$DB_FILE")
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "db_modified": $DB_MODIFIED,
    "default_gratuity": "$GRATUITY_VAL",
    "service_charge": "$SERVICE_CHARGE_VAL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="