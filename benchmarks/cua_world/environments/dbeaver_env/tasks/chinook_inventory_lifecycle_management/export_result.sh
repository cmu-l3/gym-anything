#!/bin/bash
# Export script for chinook_inventory_lifecycle_management
# Verifies schema changes and data updates in the SQLite database

echo "=== Exporting Inventory Lifecycle Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
REPORT_PATH="/home/ga/Documents/exports/archival_summary.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
SCHEMA_CORRECT="false"
COLUMN_TYPE=""
DEFAULT_VALUE=""
UPDATE_PRECISION=0.0
UPDATE_RECALL=0.0
ACTIVE_MISTAKENLY_ARCHIVED=0
DEAD_MISSED_ARCHIVAL=0
REPORT_EXISTS="false"
REPORT_SCORE=0

# Check Schema
if [ -f "$DB_PATH" ]; then
    # Get column info: cid|name|type|notnull|dflt_value|pk
    COL_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(tracks);" | grep -i "IsArchived" || echo "")
    
    if [ -n "$COL_INFO" ]; then
        SCHEMA_CORRECT="true"
        # Extract type (3rd field) and default (5th field)
        COLUMN_TYPE=$(echo "$COL_INFO" | cut -d'|' -f3)
        DEFAULT_VALUE=$(echo "$COL_INFO" | cut -d'|' -f5)
    fi
    
    # Verify Data Logic using Python to handle the logic check cleanly
    python3 << 'PYEOF' > /tmp/db_logic_check.json
import sqlite3
import json
import os

db_path = "/home/ga/Documents/databases/chinook.db"
result = {
    "active_mistakenly_archived": 0,
    "dead_missed_archival": 0,
    "total_active_2013": 0,
    "total_dead_stock": 0,
    "precision": 0.0,
    "recall": 0.0,
    "db_accessible": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # Check if column exists first to avoid crash
        try:
            c.execute("SELECT IsArchived FROM tracks LIMIT 1")
            result["db_accessible"] = True
            
            # 1. Identify tracks SOLD in 2013 (Should be Active / IsArchived=0)
            query_sold = """
                SELECT DISTINCT t.TrackId
                FROM tracks t
                JOIN invoice_items ii ON t.TrackId = ii.TrackId
                JOIN invoices i ON ii.InvoiceId = i.InvoiceId
                WHERE i.InvoiceDate LIKE '2013-%'
            """
            sold_ids = set([row[0] for row in c.execute(query_sold).fetchall()])
            result["total_active_2013"] = len(sold_ids)
            
            # 2. Get current status of ALL tracks
            c.execute("SELECT TrackId, IsArchived FROM tracks")
            all_tracks = c.fetchall()
            
            # Analyze
            fp = 0 # False Positive: Was sold (Active) but marked Archived (1)
            fn = 0 # False Negative: Was NOT sold (Dead) but marked Active (0)
            tp = 0 # True Positive: Was NOT sold (Dead) and marked Archived (1)
            tn = 0 # True Negative: Was sold (Active) and marked Active (0)
            
            for tid, status in all_tracks:
                # Handle NULLs if agent didn't set default properly
                is_archived = 1 if (status == 1 or status == '1') else 0
                
                if tid in sold_ids:
                    # SHOULD BE ACTIVE (0)
                    if is_archived == 1:
                        fp += 1
                    else:
                        tn += 1
                else:
                    # SHOULD BE ARCHIVED (1)
                    if is_archived == 1:
                        tp += 1
                    else:
                        fn += 1
            
            result["active_mistakenly_archived"] = fp
            result["dead_missed_archival"] = fn
            result["total_dead_stock"] = tp + fn
            
            # Precision: Of those marked archived, how many were actually dead stock?
            total_marked_archived = tp + fp
            if total_marked_archived > 0:
                result["precision"] = tp / total_marked_archived
            else:
                result["precision"] = 0.0 if (tp+fn) > 0 else 1.0 # If no dead stock existed, 0 marked is perfect
                
            # Recall: Of actual dead stock, how many were marked?
            total_dead = tp + fn
            if total_dead > 0:
                result["recall"] = tp / total_dead
            else:
                result["recall"] = 1.0
                
        except Exception as e:
            result["error"] = str(e)
            
    except Exception as e:
        result["connection_error"] = str(e)

print(json.dumps(result))
PYEOF

    # Load Python results into bash variables
    if [ -f /tmp/db_logic_check.json ]; then
        UPDATE_PRECISION=$(python3 -c "import json; print(json.load(open('/tmp/db_logic_check.json')).get('precision', 0))")
        UPDATE_RECALL=$(python3 -c "import json; print(json.load(open('/tmp/db_logic_check.json')).get('recall', 0))")
        ACTIVE_MISTAKENLY_ARCHIVED=$(python3 -c "import json; print(json.load(open('/tmp/db_logic_check.json')).get('active_mistakenly_archived', 0))")
        DEAD_MISSED_ARCHIVAL=$(python3 -c "import json; print(json.load(open('/tmp/db_logic_check.json')).get('dead_missed_archival', 0))")
    fi
fi

# Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Basic check for headers
    HEADER=$(head -1 "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"genrename"* && "$HEADER" == *"archivalrate"* ]]; then
        REPORT_SCORE=10
    else
        REPORT_SCORE=5
    fi
fi

# Check if app was running
APP_RUNNING=$(is_dbeaver_running)

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "schema_correct": $SCHEMA_CORRECT,
    "column_type": "$COLUMN_TYPE",
    "default_value": "$DEFAULT_VALUE",
    "update_precision": $UPDATE_PRECISION,
    "update_recall": $UPDATE_RECALL,
    "active_mistakenly_archived": $ACTIVE_MISTAKENLY_ARCHIVED,
    "dead_missed_archival": $DEAD_MISSED_ARCHIVAL,
    "report_exists": $REPORT_EXISTS,
    "report_score": $REPORT_SCORE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
cp /tmp/task_result.json /tmp/safe_task_result.json
chmod 666 /tmp/safe_task_result.json

echo "Export Complete. Result:"
cat /tmp/safe_task_result.json