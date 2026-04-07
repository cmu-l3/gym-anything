#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Water Energy Demand Results ==="

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Basic Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Files
CSV_PATH="/home/ga/LCA_Results/water_energy_demand.csv"
TXT_PATH="/home/ga/LCA_Results/water_energy_summary.txt"

check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"size\": $size, \"fresh\": true}"
        else
            echo "{\"exists\": true, \"size\": $size, \"fresh\": false}"
        fi
    else
        echo "{\"exists\": false, \"size\": 0, \"fresh\": false}"
    fi
}

CSV_INFO=$(check_file "$CSV_PATH")
TXT_INFO=$(check_file "$TXT_PATH")

# 4. Check OpenLCA Internal State (via Derby)
# We need to close OpenLCA to safely query the Derby DB without locks,
# OR we try querying live (task_utils.sh handles retries).
# For robustness in export, we'll try to keep it open if possible, but
# closing ensures data is flushed to disk.
close_openlca
sleep 3

# Find the active database (usually the largest one modified recently)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

for db in "$DB_DIR"/*/; do
    if [ -d "$db" ]; then
        size=$(du -sm "$db" 2>/dev/null | cut -f1)
        if [ "$size" -gt "$MAX_SIZE" ]; then
            MAX_SIZE=$size
            ACTIVE_DB=$db
        fi
    fi
done

DB_STATS="{}"
if [ -n "$ACTIVE_DB" ]; then
    # Count tables
    PROC_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES")
    SYS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    FLOW_COUNT=$(derby_count "$ACTIVE_DB" "FLOWS")
    IMPACT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES")

    # Get Product System Names (to check for 'water')
    # We use a raw query to get names of product systems
    PS_NAMES=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_PRODUCT_SYSTEMS" 2>/dev/null | grep -v "ij>" | grep -v "rows selected" | tr '\n' ',' | sed 's/,,/,/g')

    DB_STATS="{\"processes\": $PROC_COUNT, \"product_systems\": $SYS_COUNT, \"flows\": $FLOW_COUNT, \"impact_categories\": $IMPACT_COUNT, \"system_names\": \"$PS_NAMES\"}"
else
    DB_STATS="{\"error\": \"No database found\"}"
fi

# 5. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_file": $CSV_INFO,
    "txt_file": $TXT_INFO,
    "database_stats": $DB_STATS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json