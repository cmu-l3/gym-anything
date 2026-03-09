#!/system/bin/sh
# Export script for record_vineyard_maturity_sampling task.
# Extracts SQLite database data and captures screenshots.

echo "=== Exporting results for Vineyard Maturity task ==="

PACKAGE="org.farmos.app"
DB_PATH="/data/data/$PACKAGE/databases/farmos.db"
RESULT_FILE="/sdcard/task_result.json"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved to /sdcard/final_screenshot.png"

# 2. Dump UI Hierarchy (for potential VLM debugging)
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# 3. Extract Data from SQLite Database
# We need to switch to root/su to access the app's private database
# We will construct a JSON object manually since we might not have jq

echo "Extracting database records..."

# Create a temporary extraction script to run as root
cat > /sdcard/extract_db.sh << 'EOF'
#!/system/bin/sh
DB="/data/data/org.farmos.app/databases/farmos.db"

# Check if sqlite3 is available
if ! which sqlite3 >/dev/null; then
    echo "{\"error\": \"sqlite3 not found\"}"
    exit 1
fi

# Query for the specific log
# We look for the most recently created observation log
LOG_QUERY="SELECT id, timestamp, type, notes FROM logs WHERE type='farm_observation' ORDER BY id DESC LIMIT 1;"
LOG_DATA=$(sqlite3 "$DB" "$LOG_QUERY" 2>/dev/null)

if [ -z "$LOG_DATA" ]; then
    echo "{\"log_found\": false}"
    exit 0
fi

# Parse log data (assuming pipe delimiter default)
LOG_ID=$(echo "$LOG_DATA" | awk -F'|' '{print $1}')
LOG_TIMESTAMP=$(echo "$LOG_DATA" | awk -F'|' '{print $2}')
LOG_TYPE=$(echo "$LOG_DATA" | awk -F'|' '{print $3}')
# Notes might contain pipes or newlines, simpler to grab separately or assume simple text
# For safety, we'll fetch notes separately to handle quoting better in a real script, 
# but here we'll trust the simple awk split for the basic structure.
LOG_NOTES=$(echo "$LOG_DATA" | awk -F'|' '{print $4}')

# Query for quantities associated with this log
# Quantities table usually links via log_id
QTY_QUERY="SELECT measure, units, label FROM quantities WHERE log_id=$LOG_ID;"
QTY_DATA=$(sqlite3 "$DB" "$QTY_QUERY")

# Format quantities as JSON array
QTY_JSON="["
FIRST=1
# Read line by line
echo "$QTY_DATA" | while IFS='|' read -r VAL UNIT LABEL; do
    if [ -z "$VAL" ]; then continue; fi
    if [ "$FIRST" -eq 0 ]; then QTY_JSON="$QTY_JSON,"; fi
    QTY_JSON="$QTY_JSON {\"value\": \"$VAL\", \"unit\": \"$UNIT\", \"label\": \"$LABEL\"}"
    FIRST=0
done
QTY_JSON="$QTY_JSON ]"

# Construct final JSON
echo "{"
echo "  \"log_found\": true,"
echo "  \"id\": \"$LOG_ID\","
echo "  \"timestamp\": \"$LOG_TIMESTAMP\","
echo "  \"type\": \"$LOG_TYPE\","
echo "  \"notes\": \"$LOG_NOTES\","
echo "  \"quantities\": $QTY_JSON"
echo "}"
EOF

# Run extraction as root
su 0 sh /sdcard/extract_db.sh > "$RESULT_FILE"

# If the extraction script failed or produced empty output, write a fallback
if [ ! -s "$RESULT_FILE" ]; then
    echo "{\"error\": \"Database extraction failed or returned empty\"}" > "$RESULT_FILE"
fi

chmod 666 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"