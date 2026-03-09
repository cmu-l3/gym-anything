#!/bin/bash
echo "=== Exporting assign_cash_drawer results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (visual evidence)
take_screenshot /tmp/task_final.png

# 2. Stop Floreant POS to release Derby database lock
# (Derby in embedded mode locks the DB file, preventing external queries)
echo "Stopping Floreant POS for database verification..."
kill_floreant

# 3. Query the database for drawer assignment history
# We look for the most recent entry in DRAWER_ASSIGNED_HISTORY
DB_PATH="/opt/floreantpos/database/derby-server/posdb"
EXPORT_JSON="/tmp/task_result.json"

echo "Querying Derby database..."

# specific SQL to get the last assignment
# Note: Table names in Derby are often uppercase. 
# We select relevant columns to verify: TIME, OPERATION, AMOUNT (if stored here or in separate cash drop table)
# In Floreant schema, DRAWER_ASSIGNED_HISTORY usually tracks this.

# Create SQL script
cat > /tmp/query_drawer.sql << EOF
connect 'jdbc:derby:$DB_PATH';
SELECT * FROM DRAWER_ASSIGNED_HISTORY ORDER BY ID DESC FETCH FIRST 5 ROWS ONLY;
EOF

# Execute SQL using Derby 'ij' tool
# We need to find where ij is or run java with derbytools
DERBY_TOOLS_JAR=$(find /opt/floreantpos -name "derbytools.jar" | head -1)
DERBY_CLIENT_JAR=$(find /opt/floreantpos -name "derbyclient.jar" | head -1)
DERBY_SHARED_JAR=$(find /opt/floreantpos -name "derbyshared.jar" | head -1)
FLOREANT_LIB="/opt/floreantpos/lib"

# Construct classpath
CP="$DERBY_TOOLS_JAR:$DERBY_CLIENT_JAR:$DERBY_SHARED_JAR:$FLOREANT_LIB/*"

# Run query and capture output
echo "Running SQL query..."
java -cp "$CP" org.apache.derby.tools.ij /tmp/query_drawer.sql > /tmp/db_query_raw.txt 2>&1

echo "Raw DB Output:"
cat /tmp/db_query_raw.txt

# 4. Parse output and create JSON result
# We do a rough parse here, or let python do it. 
# For robustness, we'll save the raw text and let python parse it, 
# but we'll also try to extract the specific float amount if visible.

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Create a JSON with the raw query output for the verifier to parse
# We use python to safely escape the text content into JSON
python3 -c "
import json
import sys
import time

try:
    with open('/tmp/db_query_raw.txt', 'r', errors='ignore') as f:
        raw_db = f.read()
except:
    raw_db = ''

result = {
    'task_start': $TASK_START_TIME,
    'task_end': $TASK_END_TIME,
    'db_output': raw_db,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$EXPORT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 "$EXPORT_JSON"

echo "=== Export complete ==="