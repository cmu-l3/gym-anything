#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_user_type task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Start Floreant POS and show main terminal
# This ensures the agent starts with the UI ready
start_and_login
sleep 5

# 2. Record initial database state
# We need to query the embedded Derby DB. Since the app is running (and locking the DB),
# we rely on a pre-check or assume a clean state based on the environment reset.
# However, to be robust, we will try to read the current max ID by briefly pausing/checking
# or just assume the verifier handles the "new vs old" check by looking for the specific string.
#
# To get a baseline count, we will rely on export_result.sh to compare against known defaults
# or simply check if the specific *new* name exists.
#
# For precise "diff", we'll save a snapshot of the DB folder metadata to ensure modifications happen.
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi
echo "$DB_PATH" > /tmp/derby_db_path.txt

# Save timestamp of DB folder to detect modifications
stat -c %Y "$DB_PATH/seg0" 2>/dev/null > /tmp/initial_db_mtime.txt || echo "0" > /tmp/initial_db_mtime.txt

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== create_user_type task setup complete ==="