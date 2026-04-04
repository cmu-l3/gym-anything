#!/bin/bash
echo "=== Setting up Create Custom Order Type task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous 'Curbside' order type to ensure a fresh start
# We use the Derby 'ij' tool to execute a delete command
echo "Cleaning up any existing 'Curbside' order type..."
IJ_SCRIPT="/tmp/cleanup_ordertype.sql"
cat > "$IJ_SCRIPT" <<EOF
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
DELETE FROM ORDER_TYPE WHERE NAME = 'Curbside';
DISCONNECT;
EXIT;
EOF

# Execute cleanup (suppress output to avoid confusing logs if table doesn't exist)
java -Dderby.system.home=/opt/floreantpos/database/derby-server \
     -cp "/opt/floreantpos/lib/*" \
     org.apache.derby.tools.ij "$IJ_SCRIPT" >/dev/null 2>&1 || true

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Start Floreant POS
start_and_login

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="