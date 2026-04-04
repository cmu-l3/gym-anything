#!/bin/bash
echo "=== Exporting Chinook Schema Modernization Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

DB_PATH="/home/ga/Documents/databases/chinook_legacy.db"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Python script to analyze the database and config
cat > /tmp/analyze_result.py << 'PYEOF'
import sqlite3
import json
import os
import sys

db_path = sys.argv[1]
config_path = sys.argv[2]
result = {
    "connection_exists": False,
    "connection_name_correct": False,
    "db_exists": False,
    "orphaned_invoices_count": -1,
    "orphaned_items_count": -1,
    "invoice_fk_exists": False,
    "item_fk_exists": False,
    "cascade_configured": False,
    "last_modified": 0
}

# 1. Check DBeaver Config
if os.path.exists(config_path):
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
            # Search connections
            for conn_id, conn_data in config.get('connections', {}).items():
                name = conn_data.get('name', '')
                if 'chinooklegacy' in name.lower().replace(' ', ''):
                    result["connection_exists"] = True
                    if name == "ChinookLegacy":
                        result["connection_name_correct"] = True
                    # Check if path matches
                    db_conf = conn_data.get('configuration', {}).get('database', '')
                    if 'chinook_legacy.db' in db_conf:
                        pass # Path confirmed
    except Exception as e:
        print(f"Config error: {e}")

# 2. Check Database State
if os.path.exists(db_path):
    result["db_exists"] = True
    result["last_modified"] = os.path.getmtime(db_path)
    
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        
        # Check Orphans
        cur.execute("SELECT COUNT(*) FROM invoices WHERE CustomerId NOT IN (SELECT CustomerId FROM customers)")
        result["orphaned_invoices_count"] = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices)")
        result["orphaned_items_count"] = cur.fetchone()[0]
        
        # Check Schema for FKs
        # In SQLite, we check sqlite_master sql definition
        
        # Invoices FK
        cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='invoices'")
        row = cur.fetchone()
        if row and row[0]:
            sql = row[0].upper()
            # Look for REFERENCES CUSTOMERS
            if "REFERENCES CUSTOMERS" in sql or 'REFERENCES "CUSTOMERS"' in sql:
                result["invoice_fk_exists"] = True
        
        # Invoice Items FK and Cascade
        cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='invoice_items'")
        row = cur.fetchone()
        if row and row[0]:
            sql = row[0].upper()
            # Look for REFERENCES INVOICES
            if "REFERENCES INVOICES" in sql or 'REFERENCES "INVOICES"' in sql:
                result["item_fk_exists"] = True
                # Look for ON DELETE CASCADE
                if "ON DELETE CASCADE" in sql:
                    result["cascade_configured"] = True
                    
        conn.close()
    except Exception as e:
        print(f"DB Error: {e}")

# Output JSON
print(json.dumps(result))
PYEOF

# Run analysis
python3 /tmp/analyze_result.py "$DB_PATH" "$DBEAVER_CONFIG" > /tmp/task_result.json

# Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo 0)
MODIFIED_DURING_TASK="false"
if [ "$DB_MTIME" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# Append timestamp info to JSON using jq or python override
# Since jq might not be there, use python to merge
python3 -c "
import json
with open('/tmp/task_result.json', 'r') as f:
    d = json.load(f)
d['modified_during_task'] = $MODIFIED_DURING_TASK
d['task_start'] = $TASK_START
d['screenshot_path'] = '/tmp/task_final.png'
with open('/tmp/task_result.json', 'w') as f:
    json.dump(d, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="