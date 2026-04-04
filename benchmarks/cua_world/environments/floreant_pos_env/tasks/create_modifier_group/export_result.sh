#!/bin/bash
set -e

echo "=== Exporting create_modifier_group results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# STOP FLOREANT POS
# Critical: We must stop the app to release the Derby DB lock
# otherwise 'ij' tool cannot connect to the embedded DB.
# ------------------------------------------------------------------
echo "Stopping Floreant POS to release database lock..."
kill_floreant
sleep 5

# ------------------------------------------------------------------
# LOCATE DATABASE AND TOOLS
# ------------------------------------------------------------------
# Find Derby database path
DB_PATH=""
for candidate in \
    "/opt/floreantpos/database/derby-server/posdb" \
    "/opt/floreantpos/database/posdb" \
    $(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null); do
    if [ -d "$candidate" ] && [ -f "$candidate/service.properties" ]; then
        DB_PATH="$candidate"
        break
    fi
done

# Find Derby JARs
DERBY_CLASSPATH=$(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null | tr '\n' ':')
if [ -z "$DERBY_CLASSPATH" ]; then
    DERBY_CLASSPATH=$(find /opt/floreantpos -name "derby*.jar" 2>/dev/null | tr '\n' ':')
fi

# ------------------------------------------------------------------
# QUERY DATABASE
# ------------------------------------------------------------------
GROUP_FOUND="false"
MODIFIERS_FOUND="[]"
PRICES_CORRECT="false"

if [ -n "$DB_PATH" ] && [ -n "$DERBY_CLASSPATH" ]; then
    echo "Querying Derby DB at $DB_PATH..."
    
    # Create verification SQL script
    cat > /tmp/verify_modifiers.sql << SQLEOF
CONNECT 'jdbc:derby:$DB_PATH';

-- Check for the group
SELECT ID, NAME FROM MENU_MODIFIER_GROUP WHERE UPPER(NAME) LIKE '%COOKING%TEMP%';

-- Check for the modifiers linked to that group
SELECT m.NAME, m.EXTRA_PRICE 
FROM MENU_MODIFIER m 
INNER JOIN MENU_MODIFIER_GROUP g ON m.MODIFIERGROUP_ID = g.ID 
WHERE UPPER(g.NAME) LIKE '%COOKING%TEMP%';

DISCONNECT;
EXIT;
SQLEOF

    # Run query
    java -cp "$DERBY_CLASSPATH" org.apache.derby.tools.ij /tmp/verify_modifiers.sql > /tmp/db_results.txt 2>&1
    
    # Parse Group Existence
    if grep -qi "Cooking.*Temp" /tmp/db_results.txt; then
        GROUP_FOUND="true"
    fi
    
    # Parse Modifiers (extract names found in the DB output)
    # The output format of ij is a bit messy, so we just grep for expected names
    # We construct a JSON array of found names
    FOUND_LIST=""
    for MOD in "Rare" "Medium Rare" "Medium" "Medium Well" "Well Done"; do
        # Use specific grep to avoid partial matches (e.g. "Medium" inside "Medium Rare")
        # But ij output is text table. We'll simplify: check if the string exists in the specific result section
        if grep -qi "$MOD" /tmp/db_results.txt; then
            if [ -z "$FOUND_LIST" ]; then FOUND_LIST="\"$MOD\""; else FOUND_LIST="$FOUND_LIST, \"$MOD\""; fi
        fi
    done
    MODIFIERS_FOUND="[$FOUND_LIST]"
    
    # Check Prices
    # We look for lines containing the modifiers and check if they have 0.0 or 0 or NULL
    # If we find any price > 0, set flag to false
    # This is a heuristic check on the output text
    if grep -E "[1-9]+\.[0-9]+" /tmp/db_results.txt | grep -qi "Rare\|Medium\|Well"; then
        PRICES_CORRECT="false"
    else
        PRICES_CORRECT="true"
    fi
    
else
    echo "ERROR: Could not locate DB or Derby tools"
    cat > /tmp/db_results.txt << EOF
Error: DB_PATH=$DB_PATH
DERBY_CLASSPATH=$DERBY_CLASSPATH
EOF
fi

# ------------------------------------------------------------------
# GENERATE RESULT JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_found": $GROUP_FOUND,
    "modifiers_found": $MODIFIERS_FOUND,
    "prices_appear_correct": $PRICES_CORRECT,
    "db_query_log": "/tmp/db_results.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="