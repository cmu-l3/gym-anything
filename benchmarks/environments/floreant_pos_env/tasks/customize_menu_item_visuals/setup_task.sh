#!/bin/bash
set -e
echo "=== Setting up customize_menu_item_visuals task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance
kill_floreant

# 2. Restore clean database to ensure item doesn't exist
# This matches the pattern in example process_order task
echo "Restoring clean database snapshot..."
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_DIR" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback layout
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
fi

# 3. Record initial item count (Anti-gaming)
# We need to construct the classpath for Derby tools
FLOREANT_LIB="/opt/floreantpos/lib"
CLASSPATH="$FLOREANT_LIB/derby.jar:$FLOREANT_LIB/derbytools.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server"

# Create a SQL script to count items
cat > /tmp/count_items.sql << EOF
CONNECT '$DB_URL';
SELECT COUNT(*) FROM MENU_ITEM;
EXIT;
EOF

# Run query
echo "Recording initial menu item count..."
INITIAL_COUNT_OUTPUT=$(java -cp "$CLASSPATH" -Dderby.system.home=/opt/floreantpos org.apache.derby.tools.ij /tmp/count_items.sql 2>/dev/null || echo "0")
# Extract the number (ij output is verbose)
INITIAL_COUNT=$(echo "$INITIAL_COUNT_OUTPUT" | grep -A 1 "1" | tail -1 | tr -d ' ' | grep -o "[0-9]*" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt
echo "Initial item count: $INITIAL_COUNT"

# 4. Start Floreant POS
start_and_login

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="