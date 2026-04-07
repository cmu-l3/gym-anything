#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Hotspot Analysis Results ==="

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Get Timing Information
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze Output Files
REPORT_PATH="/home/ga/LCA_Results/hotspot_report.csv"
SUMMARY_PATH="/home/ga/LCA_Results/hotspot_summary.txt"

check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false, \"path\": \"$fpath\"}"
    fi
}

REPORT_INFO=$(check_file "$REPORT_PATH")
SUMMARY_INFO=$(check_file "$SUMMARY_PATH")

# 4. Inspect OpenLCA Internal State (Derby Database)
# We need to know if the database was imported and product system created
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the largest/most active database
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DB_METRICS="{}"
if [ -n "$ACTIVE_DB" ]; then
    # Query Derby counts (requires OpenLCA to be closed or non-locking mode, using helper)
    # Note: derby_query in task_utils handles connection
    
    # Check 1: Processes (Did they import USLCI?)
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
    
    # Check 2: Product Systems (Did they create one?)
    SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    
    # Check 3: Impact Categories (Did they import LCIA methods?)
    IMPACT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
    
    DB_METRICS="{\"db_found\": true, \"process_count\": $PROCESS_COUNT, \"product_system_count\": $SYSTEM_COUNT, \"impact_category_count\": $IMPACT_COUNT, \"size_mb\": $MAX_SIZE}"
else
    DB_METRICS="{\"db_found\": false, \"process_count\": 0, \"product_system_count\": 0, \"impact_category_count\": 0, \"size_mb\": 0}"
fi

# 5. Check Application State
APP_RUNNING=$(is_openlca_running && echo "true" || echo "false")

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_file": $REPORT_INFO,
    "summary_file": $SUMMARY_INFO,
    "database_state": $DB_METRICS,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json