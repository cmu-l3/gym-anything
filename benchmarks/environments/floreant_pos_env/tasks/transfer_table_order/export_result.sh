#!/bin/bash
echo "=== Exporting transfer_table_order result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Stop the application to release the Derby database lock
# We cannot query the embedded Derby DB reliably while the app is writing to it
echo "Stopping Floreant POS for database verification..."
kill_floreant

# 3. Query the Derby Database
# We look for open tickets and their assigned tables
echo "Querying database..."

DB_PATH="/opt/floreantpos/database/derby-server/posdb"
RESULT_JSON="/tmp/task_result.json"

# Create a SQL script to extract verification data
# We select: Ticket ID, Table Number, Closed Status, Item Count
cat > /tmp/verify_query.sql << SQL
CONNECT 'jdbc:derby:${DB_PATH}';

SELECT 
    t.ID AS TICKET_ID, 
    st.TABLE_NUMBER, 
    t.CLOSED, 
    (SELECT COUNT(*) FROM TICKET_ITEM ti WHERE ti.TICKET_ID = t.ID) AS ITEM_COUNT
FROM TICKET t 
JOIN SHOP_TABLE st ON t.SHOP_TABLE_ID = st.ID 
WHERE t.CLOSED = false OR t.CLOSED IS NULL;

DISCONNECT;
EXIT;
SQL

# Execute query using ij (Derby tool)
# We need to construct the classpath to include derby jars and the app jar
CP="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"

# run ij and capture output
QUERY_OUTPUT=$(java -cp "$CP" org.apache.derby.tools.ij /tmp/verify_query.sql 2>&1)

echo "--- raw query output ---"
echo "$QUERY_OUTPUT"
echo "------------------------"

# 4. Parse the output into JSON
# The output of ij is a text table. We'll parse it with Python for robustness.
python3 -c "
import sys
import json
import re

output = sys.stdin.read()
tickets = []

# Regex to parse the ij output table rows
# Row format roughly: ID | TABLE_NUM | CLOSED | ITEM_COUNT
# Example: 123 | 7 | false | 2
# We look for lines containing numbers and pipes
for line in output.splitlines():
    # skip headers/metadata
    if 'rows selected' in line or 'CONNECT' in line:
        continue
        
    parts = [p.strip() for p in line.split('|')]
    if len(parts) >= 4 and parts[1].isdigit():
        try:
            tickets.append({
                'id': parts[0],
                'table_number': int(parts[1]),
                'closed': parts[2].lower() == 'true',
                'item_count': int(parts[3])
            })
        except ValueError:
            continue

result = {
    'open_tickets': tickets,
    'timestamp': '$(date +%s)',
    'screenshot_exists': True
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
" <<< "$QUERY_OUTPUT"

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Exported JSON result:"
cat "$RESULT_JSON"
echo "=== Export complete ==="