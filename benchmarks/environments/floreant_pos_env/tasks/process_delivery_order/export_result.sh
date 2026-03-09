#!/bin/bash
echo "=== Exporting Process Delivery Order Result ==="

source /workspace/scripts/task_utils.sh

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# ==============================================================================
# QUERY DATABASE FOR RESULT
# ==============================================================================
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
DERBY_LIB="/opt/floreantpos/lib"
# Include all jars in lib just to be safe, but specifically derby ones
CLASSPATH=$(echo $DERBY_LIB/*.jar | tr ' ' ':')
DB_URL="jdbc:derby:$DB_POSDB"

echo "Querying database at $DB_POSDB..."

# We need to find tickets created AFTER task start.
# Derby stores dates typically. We'll fetch the last created tickets and filter in python/bash.
# We'll query TICKET table and join with CUSTOMER if needed.
# Note: Floreant schema varies, but TICKET usually has direct customer cols or a link.
# We will select relevant columns.

cat > /tmp/verify_order.sql <<EOF
CONNECT '$DB_URL';

-- Check total count
SELECT COUNT(*) AS TOTAL_TICKETS FROM TICKET;

-- Get details of the most recent tickets (likely the one agent created)
-- We fetch last 3 to be safe
SELECT t.ID, t.CREATE_DATE, t.TICKET_TYPE, t.CLOSED, t.PAID, t.TOTAL_AMOUNT,
       t.CUSTOMER_ID, t.DELIVERY_ADDRESS, t.CUSTOMER_NAME, t.MOBILE_NO
FROM TICKET t
ORDER BY t.ID DESC
FETCH FIRST 3 ROWS ONLY;

-- Check items for the most recent ticket
SELECT t.ID AS TICKET_ID, i.ITEM_NAME, i.ITEM_COUNT
FROM TICKET t
JOIN TICKET_ITEM i ON t.ID = i.TICKET_ID
ORDER BY t.ID DESC
FETCH FIRST 10 ROWS ONLY;

-- Check customer table if linked
SELECT c.AUTO_ID, c.NAME, c.TELEPHONE_NO, c.ADDRESS, c.ZIP_CODE
FROM CUSTOMER c
ORDER BY c.AUTO_ID DESC
FETCH FIRST 3 ROWS ONLY;

EXIT;
EOF

# Execute query and capture output
QUERY_OUTPUT_FILE="/tmp/db_query_output.txt"
if [ -n "$DB_POSDB" ]; then
    java -cp "$CLASSPATH" org.apache.derby.tools.ij /tmp/verify_order.sql > "$QUERY_OUTPUT_FILE" 2>&1
else
    echo "Database not found" > "$QUERY_OUTPUT_FILE"
fi

# ==============================================================================
# PARSE RESULTS (Python helper in container)
# ==============================================================================
# We use a small embedded python script to parse the messy IJ output into JSON
# This ensures we handle the text format robustly inside the container
cat > /tmp/parse_db_result.py << 'PYEOF'
import json
import re
import sys
import time

def parse_ij_output(filename):
    try:
        with open(filename, 'r') as f:
            content = f.read()
    except:
        return {"error": "Could not read query output"}

    # Extract ticket count
    # Output looks like:
    # 1
    # -----------
    # 5
    count_match = re.search(r'TOTAL_TICKETS\s*\n\s*-+\s*\n\s*(\d+)', content)
    final_count = int(count_match.group(1)) if count_match else 0

    # Extract Tickets
    # We look for the section after the ticket query
    # ID |CREATE_DATE ...
    # ----------------
    # 15 |2023-...
    tickets = []
    # This regex is a bit loose to handle variable column widths
    # We just grab the raw lines that look like data rows (digits followed by separators)
    # A robust way is to just dump the raw content for the verifier to parse,
    # but let's try to find our specific ticket here.

    return {
        "raw_output": content,
        "final_ticket_count": final_count
    }

data = parse_ij_output("/tmp/db_query_output.txt")
print(json.dumps(data))
PYEOF

PARSED_JSON=$(python3 /tmp/parse_db_result.py)

# ==============================================================================
# CREATE FINAL RESULT JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_ticket_count": $INITIAL_COUNT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "db_data": $PARSED_JSON,
    "app_running": $(pgrep -f "floreantpos.jar" > /dev/null && echo "true" || echo "false")
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
ls -l /tmp/task_result.json