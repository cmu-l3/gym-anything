#!/bin/bash
echo "=== Exporting delete_obsolete_references results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || echo "1970-01-01")

# Get DB path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/home/ga/Jurism/jurism.sqlite"
fi

# Retrieve Target IDs
ID_OBERGEFELL=$(cat /tmp/target_obergefell.id 2>/dev/null || echo "0")
ID_GIDEON=$(cat /tmp/target_gideon.id 2>/dev/null || echo "0")
ID_POE=$(cat /tmp/target_poe.id 2>/dev/null || echo "0")

echo "Checking targets: Obergefell($ID_OBERGEFELL), Gideon($ID_GIDEON), Poe($ID_POE)"

# Helper to check if ID is in deletedItems
check_is_deleted() {
    local iid=$1
    if [ -z "$iid" ] || [ "$iid" -eq 0 ]; then
        echo "false"
        return
    fi
    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletedItems WHERE itemID=$iid" 2>/dev/null || echo "0")
    if [ "$count" -gt 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Helper to check timestamp of deletion (must be > task start)
check_deletion_time() {
    local iid=$1
    if [ -z "$iid" ] || [ "$iid" -eq 0 ]; then
        echo "false"
        return
    fi
    # dateDeleted format is typically YYYY-MM-DD HH:MM:SS
    local del_time
    del_time=$(sqlite3 "$DB_PATH" "SELECT dateDeleted FROM deletedItems WHERE itemID=$iid" 2>/dev/null || echo "")
    
    if [ -z "$del_time" ]; then
        echo "false"
        return
    fi
    
    # Simple string comparison works for ISO dates, but let's be safe
    if [[ "$del_time" > "$TASK_START_ISO" ]]; then
        echo "true"
    else
        echo "false" #(deleted before task start)
    fi
}

# Check targets
OBERGEFELL_DELETED=$(check_is_deleted "$ID_OBERGEFELL")
GIDEON_DELETED=$(check_is_deleted "$ID_GIDEON")
POE_DELETED=$(check_is_deleted "$ID_POE")

OBERGEFELL_VALID=$(check_deletion_time "$ID_OBERGEFELL")
GIDEON_VALID=$(check_deletion_time "$ID_GIDEON")
POE_VALID=$(check_deletion_time "$ID_POE")

# Check Collateral Damage (Keep items)
COLLATERAL_DAMAGE_COUNT=0
if [ -f /tmp/keep_items.ids ]; then
    while read -r keep_id; do
        if [ -n "$keep_id" ]; then
            is_del=$(check_is_deleted "$keep_id")
            if [ "$is_del" == "true" ]; then
                COLLATERAL_DAMAGE_COUNT=$((COLLATERAL_DAMAGE_COUNT + 1))
            fi
        fi
    done < /tmp/keep_items.ids
fi

# Get total Trash count
TRASH_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletedItems" 2>/dev/null || echo "0")

# Get Active Library count (Total items NOT in deletedItems)
# Exclude system types (1=attachment, 3=note, 31=annotation)
ACTIVE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")

# Check if Jurism is running
APP_RUNNING=$(pgrep -f "jurism" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "obergefell_deleted": $OBERGEFELL_DELETED,
    "obergefell_valid_time": $OBERGEFELL_VALID,
    "gideon_deleted": $GIDEON_DELETED,
    "gideon_valid_time": $GIDEON_VALID,
    "poe_deleted": $POE_DELETED,
    "poe_valid_time": $POE_VALID,
    "collateral_damage_count": $COLLATERAL_DAMAGE_COUNT,
    "total_trash_count": $TRASH_COUNT,
    "active_library_count": $ACTIVE_COUNT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="