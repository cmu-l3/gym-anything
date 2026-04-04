#!/bin/bash
set -e
echo "=== Setting up Nationality Friendship Projection Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

# Database credentials
DB="demodb"
USER="admin"
PASS="admin"

# Ensure the database exists and has the base data (Profiles, HasFriend)
# The seed_demodb.py script ran during container build, but we double check
# by querying the profile count.
echo "Checking base data..."
PROFILE_COUNT=$(curl -s -X POST \
    -u "root:GymAnything123!" \
    -H "Content-Type: application/json" \
    -d '{"command": "SELECT count(*) FROM Profiles"}' \
    "http://localhost:2480/command/${DB}/sql" | \
    python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0]['count'])" 2>/dev/null || echo "0")

if [ "$PROFILE_COUNT" -lt 5 ]; then
    echo "Base data missing or incomplete. Re-seeding..."
    python3 /workspace/scripts/seed_demodb.py
fi

# CLEANUP: Drop the target classes if they exist from a previous run
# This ensures the agent starts from a clean slate
echo "Cleaning up any previous task artifacts..."

# Drop edges first (constraints)
orientdb_sql "$DB" "DROP CLASS NationalityLink UNSAFE" > /dev/null 2>&1 || true
# Drop vertices
orientdb_sql "$DB" "DROP CLASS NationalityNode UNSAFE" > /dev/null 2>&1 || true

# Remove any old report file
rm -f /home/ga/nationality_network_report.txt

# Ensure Firefox is open to the Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="