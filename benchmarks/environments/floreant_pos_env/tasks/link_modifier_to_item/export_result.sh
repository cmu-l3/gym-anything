#!/bin/bash
echo "=== Exporting link_modifier_to_item results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Kill App (Required to release Derby DB lock for verification)
kill_floreant
sleep 3

# 3. Verify Database State
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
DERBY_CP=$(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null | tr '\n' ':')
if [ -z "$DERBY_CP" ]; then
    DERBY_CP=$(find /opt/floreantpos -name "derby.jar" 2>/dev/null | head -1)
    DERBY_TOOLS=$(find /opt/floreantpos -name "derbytools.jar" 2>/dev/null | head -1)
    DERBY_CP="${DERBY_CP}:${DERBY_TOOLS}"
fi

cat > /tmp/verify_query.sql << 'SQLEOF'
CONNECT 'jdbc:derby:DB_PATH_PLACEHOLDER';

-- Check if Item exists
SELECT COUNT(*) FROM MENU_ITEM WHERE ID = 9901;

-- Check if Modifier Group exists
SELECT COUNT(*) FROM MENU_MODIFIER_GROUP WHERE ID = 9901;

-- Check for the Link (Try standard Hibernate join table names)
SELECT COUNT(*) FROM MENU_ITEM_MODIFIER_GROUP WHERE (ITEMS_ID = 9901 AND MODIFIERGROUPS_ID = 9901) OR (MENU_ITEM_ID = 9901 AND MODIFIER_GROUP_ID = 9901);

disconnect;
exit;
SQLEOF

sed -i "s|DB_PATH_PLACEHOLDER|${DB_DIR}|g" /tmp/verify_query.sql

# Run query
echo "Running verification query..."
java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/verify_query.sql > /tmp/verification_output.txt 2>&1

# Parse Output
# IJ output usually looks like:
# 1
# -----
# 1
# (1 row affected)

# Extract counts using robust grep/awk
ITEM_EXISTS=$(grep -A 2 "SELECT COUNT(\*) FROM MENU_ITEM" /tmp/verification_output.txt | tail -n 1 | grep -o "[0-9]*" || echo "0")
GROUP_EXISTS=$(grep -A 2 "SELECT COUNT(\*) FROM MENU_MODIFIER_GROUP" /tmp/verification_output.txt | tail -n 1 | grep -o "[0-9]*" || echo "0")
LINK_COUNT=$(grep -A 2 "SELECT COUNT(\*) FROM MENU_ITEM_MODIFIER_GROUP" /tmp/verification_output.txt | tail -n 1 | grep -o "[0-9]*" || echo "0")

# 4. JSON Export
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "item_exists": $ITEM_EXISTS,
    "group_exists": $GROUP_EXISTS,
    "link_count": $LINK_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json