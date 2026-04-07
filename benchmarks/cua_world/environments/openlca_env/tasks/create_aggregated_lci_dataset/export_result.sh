#!/bin/bash
# Export script for Create Aggregated LCI Dataset task
# Post-task hook: runs AFTER the agent finishes

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Create Aggregated LCI Dataset Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

# Read baseline state
INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ============================================================
# CHECK 1: Look for exported JSON-LD zip
# ============================================================
RESULTS_DIR="/home/ga/LCA_Results"
TARGET_FILE="$RESULTS_DIR/protected_cement_lci.zip"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FMTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Also check for variations in filename
if [ "$FILE_EXISTS" = "false" ]; then
    ALT_FILE=$(find "$RESULTS_DIR" -name "*cement*.zip" -newer /tmp/task_start_screenshot.png 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        TARGET_FILE="$ALT_FILE"
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
        FILE_CREATED_DURING_TASK="true"
    fi
fi

echo "Export file found: $FILE_EXISTS ($TARGET_FILE, $FILE_SIZE bytes)"

# ============================================================
# CHECK 2: Window state before closing
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
SYSTEM_PROCESS_VISIBLE="false"

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi
# Look for evidence of system process creation/viewing
if echo "$WINDOWS_LIST" | grep -qi "System process\|Aggregated\|LCI result"; then
    SYSTEM_PROCESS_VISIBLE="true"
fi

# ============================================================
# CHECK 3: Close OpenLCA and query Derby database
# ============================================================
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PS_COUNT=0
PROCESS_FOUND="false"
IS_AGGREGATED="false"
EXCHANGE_COUNT=0
DB_SIZE_MB=0
DB_FOUND="false"

# Find the active database (largest, most likely the USLCI import)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    DB_SIZE_MB="$MAX_SIZE"
    echo "Active database: $(basename "$ACTIVE_DB") (${DB_SIZE_MB}MB)"

    # Query 1: Check for Product Systems (prerequisite)
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    PS_COUNT="${PS_COUNT:-0}"
    echo "  Product systems: $PS_COUNT"

    # Query 2: Find the target process ID by name
    # We look for "IP-Protected Cement LCI" or similar
    TARGET_NAME="IP-Protected Cement LCI"
    # Note: Derby is case-sensitive inside quotes usually, but let's try a LIKE query
    # OpenLCA tables are typically TBL_PROCESSES
    PROCESS_QUERY="SELECT ID FROM TBL_PROCESSES WHERE NAME LIKE '%Protected%Cement%' OR NAME LIKE '%System process%Cement%'"
    PROCESS_ID_RESULT=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY" 2>/dev/null)
    
    # Extract ID (removing headers)
    PROCESS_ID=$(echo "$PROCESS_ID_RESULT" | grep -oE '[0-9]+' | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_FOUND="true"
        echo "  Target process found (ID: $PROCESS_ID)"
        
        # Query 3: Check Exchange Count (Aggregation check)
        # Aggregated processes have many exchanges (elementary flows from entire supply chain)
        # A simple unit process has few (~20-50). An aggregated cement LCI should have > 100.
        EXCHANGE_QUERY="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_OWNER = $PROCESS_ID"
        EXCHANGE_RESULT=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY" 2>/dev/null)
        EXCHANGE_COUNT=$(echo "$EXCHANGE_RESULT" | grep -oE '[0-9]+' | tail -1)
        EXCHANGE_COUNT="${EXCHANGE_COUNT:-0}"
        
        echo "  Exchange count: $EXCHANGE_COUNT"
        if [ "$EXCHANGE_COUNT" -gt 100 ]; then
            IS_AGGREGATED="true"
        fi
    else
        echo "  Target process not found by name query"
    fi
else
    echo "No substantial database found"
fi

# ============================================================
# Write result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "create_aggregated_lci_dataset",
    "openlca_running": $OPENLCA_RUNNING,
    "system_process_visible": $SYSTEM_PROCESS_VISIBLE,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "process_found": $PROCESS_FOUND,
    "exchange_count": ${EXCHANGE_COUNT:-0},
    "is_aggregated": $IS_AGGREGATED,
    "file_exists": $FILE_EXISTS,
    "file_size": ${FILE_SIZE:-0},
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_path": "$TARGET_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json