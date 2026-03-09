#!/bin/bash
# Export script for chinook_storage_optimization task

echo "=== Exporting Chinook Storage Optimization Result ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook_bloated.db"
ARCHIVE_PATH="/home/ga/Documents/exports/audit_archive.csv"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check DBeaver Connection ---
CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    CONNECTION_FOUND=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        if 'chinookbloated' in v.get('name', '').lower().replace(' ', ''):
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo false)
fi

# --- 2. Check Archive CSV ---
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_SIZE=0

if [ -f "$ARCHIVE_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$ARCHIVE_PATH")
    # Subtract 1 for header, handle empty file case
    TOTAL_LINES=$(wc -l < "$ARCHIVE_PATH")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi
fi

# --- 3. Check Database Content & Size ---
DB_EXISTS="false"
FINAL_DB_SIZE=0
REMAINING_TOTAL=0
REMAINING_OLD=0
REMAINING_NEW=0

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    FINAL_DB_SIZE=$(stat -c%s "$DB_PATH")
    
    # Query current counts
    REMAINING_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM audit_logs;" 2>/dev/null || echo -1)
    REMAINING_OLD=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM audit_logs WHERE log_date < '2024-01-01';" 2>/dev/null || echo -1)
    REMAINING_NEW=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM audit_logs WHERE log_date >= '2024-01-01';" 2>/dev/null || echo -1)
fi

# --- 4. Load Initial State for Comparison ---
read INITIAL_OLD INITIAL_NEW < /tmp/initial_counts.txt 2>/dev/null || echo "0 0"
INITIAL_DB_SIZE=$(cat /tmp/initial_db_size.txt 2>/dev/null || echo 0)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

# Check CSV creation time
CSV_CREATED_DURING_TASK="false"
if [ -f "$ARCHIVE_PATH" ]; then
    CSV_MTIME=$(stat -c%Y "$ARCHIVE_PATH" 2>/dev/null)
    if [ "$CSV_MTIME" -gt "$TASK_START_TIME" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Generate result JSON
cat > /tmp/task_result.json << EOF
{
    "connection_found": $CONNECTION_FOUND,
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_size_bytes": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "db_exists": $DB_EXISTS,
    "initial_db_size_bytes": $INITIAL_DB_SIZE,
    "final_db_size_bytes": $FINAL_DB_SIZE,
    "initial_old_count": ${INITIAL_OLD:-0},
    "initial_new_count": ${INITIAL_NEW:-0},
    "remaining_total_count": $REMAINING_TOTAL,
    "remaining_old_count": $REMAINING_OLD,
    "remaining_new_count": $REMAINING_NEW,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="