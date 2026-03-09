#!/bin/bash
echo "=== Exporting Configure Variable Price Item result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --------------------------------------------------------------------------
# Query Derby Database for verification
# --------------------------------------------------------------------------
# We need to export:
# 1. The definition of 'Fresh Catch' (to ensure base price isn't 42.50)
# 2. The ticket item record (to ensure it WAS sold at 42.50)

# Find Derby JARs
LIB_DIR="/opt/floreantpos/lib"
DERBY_CP=$(find "$LIB_DIR" -name "derby*.jar" | tr '\n' ':')
DB_PATH="/opt/floreantpos/database/derby-server/posdb"

# Create SQL script
cat > /tmp/verify_query.sql << SQLEOF
CONNECT 'jdbc:derby:$DB_PATH';

-- Check 1: Menu Item Definition
SELECT ID, NAME, PRICE, VISIBLE FROM MENU_ITEM WHERE NAME = 'Fresh Catch';

-- Check 2: Ticket Item (Transaction)
-- We join TICKET_ITEM with TICKET to ensure we get items from tickets created recently
-- Note: TICKET_ITEM usually stores the final price in ITEM_PRICE or UNIT_PRICE
SELECT ti.NAME, ti.ITEM_PRICE, ti.UNIT_PRICE, t.ID, t.CREATE_TIME 
FROM TICKET_ITEM ti 
JOIN TICKET t ON ti.TICKET_ID = t.ID 
WHERE ti.NAME = 'Fresh Catch' 
ORDER BY t.ID DESC;

DISCONNECT;
EXIT;
SQLEOF

# Run SQL query using ij tool
echo "Running database verification query..."
# We use 'su - ga' to ensure we have permissions if DB is owned by ga
# We also need to set CLASSPATH correctly
su - ga -c "java -cp $DERBY_CP:.:/opt/floreantpos/floreantpos.jar org.apache.derby.tools.ij /tmp/verify_query.sql" > /tmp/db_raw_output.txt 2>&1

echo "Raw DB Output:"
cat /tmp/db_raw_output.txt

# --------------------------------------------------------------------------
# Parse output to JSON
# --------------------------------------------------------------------------
# We'll use a python script to parse the messy ij output into a clean JSON
# ij output looks like:
# ID         |NAME                |PRICE     |VISIBLE
# ---------------------------------------------------
# 123        |Fresh Catch         |0.0       |true

cat > /tmp/parse_db_result.py << PYEOF
import json
import re
import sys

def parse_ij_output(filename):
    results = {
        "menu_items": [],
        "ticket_items": []
    }
    
    with open(filename, 'r') as f:
        content = f.read()

    # Split into sections based on queries (rough heuristic)
    # We look for the dashed lines that separate headers from data
    
    lines = content.split('\n')
    current_section = None
    
    for i, line in enumerate(lines):
        if "SELECT ID, NAME, PRICE" in line:
            current_section = "menu_items"
            continue
        if "SELECT ti.NAME, ti.ITEM_PRICE" in line:
            current_section = "ticket_items"
            continue
            
        # Parse data rows
        # Derby output rows usually have pipe | separators
        if '|' in line and not '---' in line and not 'ID' in line and not 'ti.NAME' in line:
            parts = [p.strip() for p in line.split('|')]
            
            if current_section == "menu_items" and len(parts) >= 3:
                try:
                    price = float(parts[2])
                    results["menu_items"].append({
                        "name": parts[1],
                        "price": price
                    })
                except ValueError:
                    pass
                    
            if current_section == "ticket_items" and len(parts) >= 3:
                try:
                    # ti.NAME | ITEM_PRICE | UNIT_PRICE | ID | CREATE_TIME
                    name = parts[0]
                    item_price = float(parts[1])
                    unit_price = float(parts[2])
                    results["ticket_items"].append({
                        "name": name,
                        "item_price": item_price,
                        "unit_price": unit_price
                    })
                except ValueError:
                    pass

    return results

try:
    data = parse_ij_output("/tmp/db_raw_output.txt")
    print(json.dumps(data, indent=2))
except Exception as e:
    print(json.dumps({"error": str(e), "menu_items": [], "ticket_items": []}))
PYEOF

python3 /tmp/parse_db_result.py > /tmp/db_parsed.json

# Check if application is running
APP_RUNNING=$(pgrep -f "floreantpos.jar" > /dev/null && echo "true" || echo "false")

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_data": $(cat /tmp/db_parsed.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="