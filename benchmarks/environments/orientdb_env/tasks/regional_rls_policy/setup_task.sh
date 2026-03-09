#!/bin/bash
set -e
echo "=== Setting up Regional RLS Policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

echo "Resetting database state..."

# Helper function to execute SQL as root
run_sql() {
    orientdb_sql "demodb" "$1" > /dev/null 2>&1 || true
}

# 1. Clean up users if they exist
run_sql "DELETE VERTEX OUser WHERE name = 'manager_eu'"
run_sql "DELETE VERTEX OUser WHERE name = 'manager_na'"

# 2. Clean up role if exists
run_sql "DELETE VERTEX ORole WHERE name = 'RegionalManager'"

# 3. Clean up RLS on Profiles (Remove _allowRead property data)
# We update all profiles to remove the field
echo "Clearing existing RLS rules..."
run_sql "UPDATE Profiles REMOVE _allowRead"

# 4. Ensure data integrity (re-verify counts)
TOTAL_PROFILES=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))")

echo "Database contains $TOTAL_PROFILES profiles."
echo "$TOTAL_PROFILES" > /tmp/initial_profile_count.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="