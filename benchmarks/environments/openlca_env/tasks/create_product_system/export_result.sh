#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Product System Result ==="

# Take final screenshot
FINAL_SCREENSHOT="/tmp/openlca_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT"
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# METHOD 1: Check window titles for evidence (before closing)
# ============================================================

WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
MODEL_GRAPH_VISIBLE="false"
PRODUCT_SYSTEM_WINDOW="false"

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi

if echo "$WINDOWS_LIST" | grep -qi "product system\|model graph\|electricity"; then
    PRODUCT_SYSTEM_WINDOW="true"
fi

if echo "$WINDOWS_LIST" | grep -qi "product system"; then
    MODEL_GRAPH_VISIBLE="true"
fi

# ============================================================
# METHOD 2: Check OpenLCA logs
# ============================================================

PS_CREATED_IN_LOG="false"
PRODUCT_SYSTEM_NAME=""
if [ -f "/tmp/openlca_ga.log" ]; then
    if grep -qi "product.system\|ProductSystem\|createProductSystem" /tmp/openlca_ga.log 2>/dev/null; then
        PS_CREATED_IN_LOG="true"
    fi
    PRODUCT_SYSTEM_NAME=$(grep -oP "(?:Product system|ProductSystem)[: ]*\K[^\n]*" /tmp/openlca_ga.log 2>/dev/null | tail -1 || echo "")
fi

# ============================================================
# METHOD 3: Close OpenLCA and query Derby for product systems
# ============================================================

close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
ACTIVE_DB_NAME=""
for db_path in "$DB_DIR"/*/; do
    db_name=$(basename "$db_path" 2>/dev/null)
    if echo "$db_name" | grep -qi "uslci\|lci\|analysis"; then
        ACTIVE_DB="$db_path"
        ACTIVE_DB_NAME="$db_name"
        break
    fi
done

if [ -z "$ACTIVE_DB" ]; then
    ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)
    ACTIVE_DB_NAME=$(basename "$ACTIVE_DB" 2>/dev/null)
fi

DB_FOUND="false"
DB_SIZE=0
PS_COUNT=0
DB_RECENTLY_MODIFIED="false"

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    DB_FOUND="true"
    DB_SIZE=$(du -sm "$ACTIVE_DB" 2>/dev/null | cut -f1)
    DB_SIZE=${DB_SIZE:-0}

    # Query Derby for product system count
    echo "  Querying Derby for product systems..."
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    echo "  Product system count: $PS_COUNT"

    if [ "$PS_COUNT" -gt 0 ] 2>/dev/null; then
        PS_CREATED_IN_LOG="true"  # Override - direct evidence

        # Try to get product system name
        PS_NAME_RESULT=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_PRODUCT_SYSTEMS FETCH FIRST 1 ROWS ONLY;" 2>/dev/null)
        PS_NAME_FROM_DB=$(echo "$PS_NAME_RESULT" | grep -v "^ij>" | grep -v "^-" | grep -v "^$" | grep -v "rows selected" | grep -v "^NAME" | head -1 | xargs)
        if [ -n "$PS_NAME_FROM_DB" ]; then
            PRODUCT_SYSTEM_NAME="$PS_NAME_FROM_DB"
        fi
    fi

    # Check for recent modifications
    RECENT_MODS=$(find "$ACTIVE_DB" -mmin -30 -type f 2>/dev/null | wc -l || echo "0")
    if [ "$RECENT_MODS" -gt 5 ]; then
        DB_RECENTLY_MODIFIED="true"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "database_found": $DB_FOUND,
    "database_name": "$ACTIVE_DB_NAME",
    "database_size_mb": $DB_SIZE,
    "openlca_running": $OPENLCA_RUNNING,
    "product_system_window": $PRODUCT_SYSTEM_WINDOW,
    "model_graph_visible": $MODEL_GRAPH_VISIBLE,
    "db_recently_modified": $DB_RECENTLY_MODIFIED,
    "ps_created_in_log": $PS_CREATED_IN_LOG,
    "ps_count": $PS_COUNT,
    "product_system_name": "$PRODUCT_SYSTEM_NAME",
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
