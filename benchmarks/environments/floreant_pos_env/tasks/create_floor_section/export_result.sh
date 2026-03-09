#!/bin/bash
echo "=== Exporting create_floor_section results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if App is running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Query Database for Results
echo "Querying database for new floor and tables..."
DERBY_LIB="/opt/floreantpos/lib"
CP="$DERBY_LIB/derby.jar:$DERBY_LIB/derbytools.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server/posdb"

# Create SQL script to dump relevant data
# Note: Table names in Derby are usually uppercase. 
# Depending on Floreant version, it might be SHOP_FLOOR and SHOP_TABLE or RESTAURANT_TABLE.
# We will query likely names.
cat > /tmp/export_data.sql << SQLEOF
CONNECT '$DB_URL';

-- Output marker
VALUES '===FLOORS===';
SELECT ID, NAME FROM SHOP_FLOOR;

-- Output marker
VALUES '===TABLES===';
-- Join tables with floors if possible, or just dump all tables
SELECT t.NAME, t.CAPACITY, f.NAME 
FROM SHOP_TABLE t JOIN SHOP_FLOOR f ON t.FLOOR_ID = f.ID 
WHERE f.NAME = 'Patio';

EXIT;
SQLEOF

# Run query
su - ga -c "java -cp $CP org.apache.derby.tools.ij /tmp/export_data.sql" > /tmp/db_export.txt 2>&1

# 4. Process DB output into variables
# Check if "Patio" exists in output
if grep -q "Patio" /tmp/db_export.txt; then
    FLOOR_CREATED="true"
else
    FLOOR_CREATED="false"
fi

# Count tables for Patio
# Look for lines like: "201 |4          |Patio"
# Clean up whitespace
TABLE_COUNT=$(grep "|Patio" /tmp/db_export.txt | wc -l)

# Check specific tables
TABLE_201_EXISTS=$(grep "201" /tmp/db_export.txt | grep "|Patio" | grep -q "|4" && echo "true" || echo "false")
TABLE_202_EXISTS=$(grep "202" /tmp/db_export.txt | grep "|Patio" | grep -q "|4" && echo "true" || echo "false")
TABLE_203_EXISTS=$(grep "203" /tmp/db_export.txt | grep "|Patio" | grep -q "|4" && echo "true" || echo "false")

# 5. Get floor count change
INITIAL_COUNT=$(cat /tmp/initial_floor_count.txt 2>/dev/null || echo "0")
# We need current count
cat > /tmp/count_floors_final.sql << SQLEOF
CONNECT '$DB_URL';
SELECT COUNT(*) FROM SHOP_FLOOR;
EXIT;
SQLEOF
FINAL_COUNT_RAW=$(su - ga -c "java -cp $CP org.apache.derby.tools.ij /tmp/count_floors_final.sql" | grep -A 1 "1" | tail -n 1 | tr -d ' ' || echo "0")
# Clean up integer
FINAL_COUNT=$(echo "$FINAL_COUNT_RAW" | grep -o "[0-9]*")

if [ -z "$FINAL_COUNT" ]; then FINAL_COUNT="0"; fi
if [ -z "$INITIAL_COUNT" ]; then INITIAL_COUNT="0"; fi

FLOOR_COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "floor_created": $FLOOR_CREATED,
    "table_count": $TABLE_COUNT,
    "table_201_correct": $TABLE_201_EXISTS,
    "table_202_correct": $TABLE_202_EXISTS,
    "table_203_correct": $TABLE_203_EXISTS,
    "floor_count_diff": $FLOOR_COUNT_DIFF,
    "screenshot_path": "/tmp/task_final.png",
    "db_export_path": "/tmp/db_export.txt"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="