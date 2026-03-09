#!/bin/bash
echo "=== Setting up add_kitchen_printer task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Record initial DB state
# We must kill Floreant to access the embedded Derby DB without locking issues
kill_floreant
sleep 2

echo "Recording initial printer count..."
# Use ij to query Derby
# We expect the table VIRTUAL_PRINTER to exist in the schema
# If query fails (e.g. table doesn't exist yet), count is 0
INITIAL_COUNT=$(java -Dderby.system.home=/opt/floreantpos/database/derby-server \
    -cp "/opt/floreantpos/lib/*" org.apache.derby.tools.ij 2>/dev/null <<EOF | grep -o "[0-9]*" | tail -1 || echo "0"
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT COUNT(*) FROM VIRTUAL_PRINTER;
EOF
)

# Clean up any potential formatting issues in the output
INITIAL_COUNT=$(echo "$INITIAL_COUNT" | tr -d '[:space:]')
if [ -z "$INITIAL_COUNT" ]; then INITIAL_COUNT="0"; fi

echo "$INITIAL_COUNT" > /tmp/initial_printer_count.txt
echo "Initial printer count: $INITIAL_COUNT"

# 3. Start Floreant POS and get to the initial state
# This utility function handles launching, waiting for window, maximizing, and focusing
start_and_login

# 4. Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="