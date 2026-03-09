#!/bin/bash
echo "=== Exporting Chinook Dynamic Pricing Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DB_PATH="/home/ga/Documents/databases/chinook_pricing.db"
CSV_PATH="/home/ga/Documents/exports/pricing_summary.csv"
SQL_PATH="/home/ga/Documents/scripts/pricing_update.sql"
GT_FILE="/var/lib/dbeaver/ground_truth/pricing_gt.json"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check DBeaver Connection
CONNECTION_OK="false"
# Parse data-sources.json looking for "ChinookPricing"
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "ChinookPricing" "$CONFIG_FILE"; then
        CONNECTION_OK="true"
    fi
fi

# 2. Check SQL Script
SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SQL_PATH")
fi

# 3. Check CSV Output
CSV_EXISTS="false"
CSV_CONTENT=""
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Convert CSV to JSON-friendly format (list of dicts)
    CSV_CONTENT=$(python3 -c "
import csv, json
try:
    with open('$CSV_PATH', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    print(json.dumps(rows))
except:
    print('[]')
")
fi

# 4. Extract Actual Database State (Current Prices)
# We need to verify what the agent actually did in the DB
DB_STATE_JSON="{}"
INVOICE_ITEMS_SYNCED="false"

if [ -f "$DB_PATH" ]; then
    # Create temp python script to dump current DB state
    cat > /tmp/dump_db_state.py << 'EOF'
import sqlite3
import json
import sys

db_path = "/home/ga/Documents/databases/chinook_pricing.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
c = conn.cursor()

# Get all current track prices
rows = c.execute("SELECT TrackId, UnitPrice FROM tracks").fetchall()
actual_prices = {row["TrackId"]: float(row["UnitPrice"]) for row in rows}

# Check invoice items consistency
# We check if there are any invoice items where UnitPrice != Track UnitPrice
# (Join should result in 0 rows if fully synced)
sync_query = """
SELECT COUNT(*) as MismatchCount
FROM invoice_items ii
JOIN tracks t ON ii.TrackId = t.TrackId
WHERE ii.UnitPrice != t.UnitPrice
"""
mismatch_count = c.execute(sync_query).fetchone()["MismatchCount"]
is_synced = (mismatch_count == 0)

# Check for modification time (anti-gaming)
import os
mtime = os.path.getmtime(db_path)

print(json.dumps({
    "actual_prices": actual_prices,
    "invoice_items_synced": is_synced,
    "db_mtime": mtime
}))
conn.close()
EOF
    
    DB_STATE_JSON=$(python3 /tmp/dump_db_state.py)
fi

# 5. Read Ground Truth (requires sudo/root usually, but we made it readable by ga or export runs as root?)
# The container usually runs export as root or has access. 
# We'll cat it into a variable.
GT_JSON=$(cat "$GT_FILE" 2>/dev/null || echo "{}")

# Assemble final JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "connection_exists": $CONNECTION_OK,
    "sql_script_exists": $SQL_EXISTS,
    "sql_script_size": $SQL_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_content": $CSV_CONTENT,
    "db_state": $DB_STATE_JSON,
    "ground_truth": $GT_JSON
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"