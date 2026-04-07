#!/bin/bash
# set -e # Don't exit on error to ensure we output JSON

source /workspace/scripts/task_utils.sh

echo "=== Exporting Database Refactor Result ==="

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Basic File Checks
LOG_FILE="/home/ga/LCA_Results/refactor_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE" | head -c 500)
fi

# 3. Close OpenLCA to unlock Derby Database for querying
echo "Closing OpenLCA for verification..."
close_openlca
sleep 5

# 4. Locate the Active Database
# The agent should have imported it. We look for the largest DB or one named USLCI.
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    # Calculate size in MB
    SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1)
    if [ "$SIZE" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="$SIZE"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active Database: $ACTIVE_DB ($MAX_SIZE MB)"

# 5. Query Derby Database
OLD_FLOW_COUNT=-1
NEW_FLOW_ID=""
NEW_FLOW_USAGE=-1
BROKEN_LINKS=-1
DB_IMPORTED="false"

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 10 ]; then
    DB_IMPORTED="true"
    
    # Query 1: Check if "Electricity, at grid, Eastern US" still exists
    # Note: escape single quotes in name if necessary, though these names don't have them
    Q_OLD="SELECT COUNT(*) FROM TBL_FLOWS WHERE NAME LIKE '%Electricity, at grid, Eastern US%';"
    OLD_FLOW_COUNT_RES=$(derby_query "$ACTIVE_DB" "$Q_OLD")
    # Extract number from ij output (format: "1 row selected\n <NUMBER>")
    OLD_FLOW_COUNT=$(echo "$OLD_FLOW_COUNT_RES" | grep -oP '^\s*\K\d+' | tail -1)
    
    # Query 2: Get ID of "Electricity, at grid, Western US"
    Q_ID="SELECT ID FROM TBL_FLOWS WHERE NAME LIKE '%Electricity, at grid, Western US%';"
    NEW_FLOW_ID_RES=$(derby_query "$ACTIVE_DB" "$Q_ID")
    NEW_FLOW_ID=$(echo "$NEW_FLOW_ID_RES" | grep -oP '^\s*\K\d+' | tail -1)
    
    # Query 3: Check usage of Western US flow in exchanges
    if [ -n "$NEW_FLOW_ID" ]; then
        Q_USAGE="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_FLOW = $NEW_FLOW_ID;"
        NEW_FLOW_USAGE_RES=$(derby_query "$ACTIVE_DB" "$Q_USAGE")
        NEW_FLOW_USAGE=$(echo "$NEW_FLOW_USAGE_RES" | grep -oP '^\s*\K\d+' | tail -1)
    else
        NEW_FLOW_USAGE=0
    fi
    
    # Query 4: Check for NULL flow references (broken links) in exchanges
    Q_BROKEN="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_FLOW IS NULL;"
    BROKEN_LINKS_RES=$(derby_query "$ACTIVE_DB" "$Q_BROKEN")
    BROKEN_LINKS=$(echo "$BROKEN_LINKS_RES" | grep -oP '^\s*\K\d+' | tail -1)
fi

# Sanitize outputs
[ -z "$OLD_FLOW_COUNT" ] && OLD_FLOW_COUNT=-1
[ -z "$NEW_FLOW_USAGE" ] && NEW_FLOW_USAGE=-1
[ -z "$BROKEN_LINKS" ] && BROKEN_LINKS=-1

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_imported": $DB_IMPORTED,
    "log_exists": $LOG_EXISTS,
    "log_content": "$(echo "$LOG_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "old_flow_count": $OLD_FLOW_COUNT,
    "new_flow_usage": $NEW_FLOW_USAGE,
    "broken_links": $BROKEN_LINKS,
    "active_db_path": "$ACTIVE_DB",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json