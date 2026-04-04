#!/bin/bash
echo "=== Exporting launch_tracked_product results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot of the UI (likely the settlement screen or main terminal)
take_screenshot /tmp/task_final.png

# 2. Stop Floreant POS to release the Derby database lock
# CRITICAL: We cannot query the embedded Derby DB while the app is running
echo "Stopping Floreant POS for database verification..."
kill_floreant
sleep 3

# 3. Setup Derby environment
DERBY_HOME="/opt/floreantpos/lib"
DERBY_CLASSPATH="$DERBY_HOME/derby.jar:$DERBY_HOME/derbytools.jar"
# Fallback if jars are elsewhere
if [ ! -f "$DERBY_HOME/derby.jar" ]; then
    DERBY_CLASSPATH=$(find /opt/floreantpos -name "derby*.jar" | tr '\n' ':')
fi

# Locate Database
POSDB_PATH=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$POSDB_PATH" ]; then
    # Fallback default
    POSDB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Using Database: $POSDB_PATH"

# 4. Query Database for Verification Data
# We need:
# A. Did the inventory items get created? What is their current stock?
# B. Did the menu item get created?
# C. Was a ticket created for that item?

SQL_SCRIPT="/tmp/verify_query.sql"
cat > "$SQL_SCRIPT" << EOF
connect 'jdbc:derby:$POSDB_PATH';

-- Check Inventory Items (Wagyu Patty, Brioche Bun)
SELECT NAME, TOTAL_PACKAGES, TOTAL_RECEIPE_UNITS FROM INVENTORY_ITEM WHERE NAME LIKE '%Wagyu%' OR NAME LIKE '%Brioche%';

-- Check Menu Item (Wagyu Burger)
SELECT NAME, PRICE FROM MENU_ITEM WHERE NAME LIKE '%Wagyu Burger%';

-- Check Ticket/Sales (Join TicketItem to Ticket)
-- We check for settled tickets containing the burger
SELECT T.ID, T.PAID_AMOUNT, TI.ITEM_NAME 
FROM TICKET T 
JOIN TICKET_ITEM TI ON T.ID = TI.TICKET_ID 
WHERE TI.ITEM_NAME LIKE '%Wagyu Burger%' AND T.CLOSED = true;

exit;
EOF

# Run Query
echo "Running database verification query..."
QUERY_OUTPUT="/tmp/db_query_output.txt"
java -cp "$DERBY_CLASSPATH" org.apache.derby.tools.ij "$SQL_SCRIPT" > "$QUERY_OUTPUT" 2>&1

# 5. Parse Output into JSON
# Doing robust parsing in bash is hard, so we'll use a python one-liner to parse the text output
# Derby output is usually formatted with separators.

python3 -c "
import json
import re
import sys

def parse_derby_output(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Extract Inventory Data
    inventory = {}
    # Look for rows like: Wagyu Patty | 99.0  | 99.0
    # Pattern: Name (text) | Val1 (double) | Val2 (double)
    inv_matches = re.findall(r'^\s*([a-zA-Z\s]+?)\s*\|\s*([0-9\.]+)\s*\|\s*([0-9\.]+)\s*$', content, re.MULTILINE)
    for name, packages, units in inv_matches:
        inventory[name.strip()] = float(packages)

    # Extract Menu Item Data
    menu_item_exists = 'Wagyu Burger' in content

    # Extract Ticket Data
    # Look for rows indicating a closed ticket with the item
    # e.g. 123 | 25.0 | Wagyu Burger
    ticket_matches = re.findall(r'^\s*([0-9]+)\s*\|\s*([0-9\.]+)\s*\|\s*(.*?Wagyu Burger.*?)\s*$', content, re.MULTILINE)
    sale_count = len(ticket_matches)

    return {
        'inventory': inventory,
        'menu_item_found': menu_item_exists,
        'sales_count': sale_count,
        'raw_output_snippet': content[:1000] # Debugging aid
    }

data = parse_derby_output('$QUERY_OUTPUT')
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# Add screenshots metadata
echo "Adding metadata..."
# (Simple JSON merge using jq is not available, using python again)
python3 -c "
import json
import os

with open('/tmp/task_result.json', 'r') as f:
    data = json.load(f)

data['screenshot_exists'] = os.path.exists('/tmp/task_final.png')
data['task_start_timestamp'] = $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

cat /tmp/task_result.json
echo "=== Export complete ==="