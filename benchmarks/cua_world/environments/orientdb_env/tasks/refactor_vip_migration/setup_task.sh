#!/bin/bash
echo "=== Setting up Refactor VIP Migration Task ==="
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

echo "Resetting state for clean start..."

# Drop classes if they exist from previous runs (in reverse dependency order)
# Ignore errors if they don't exist
orientdb_sql "demodb" "DROP CLASS ManagedBy UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Managers UNSAFE" > /dev/null 2>&1 || true

# If VIPProfiles exists, we need to move records back to Profiles before dropping to preserve data integrity for re-runs
# Or, simpler: just run the seeder again if we detect the state is dirty.
# For robustness, let's just re-seed the specific Japanese profiles if they are missing from Profiles.

if orientdb_class_exists "demodb" "VIPProfiles"; then
    echo "VIPProfiles exists. moving records back to Profiles..."
    # Move vertices back to Profiles to reset (if VIPProfiles extends Profiles, this changes the class back)
    orientdb_sql "demodb" "MOVE VERTEX (SELECT FROM VIPProfiles) TO CLASS:Profiles" > /dev/null 2>&1 || true
    orientdb_sql "demodb" "DROP CLASS VIPProfiles UNSAFE" > /dev/null 2>&1 || true
fi

# Ensure basic schema and data exists
/workspace/scripts/setup_orientdb.sh > /dev/null

# Verify Japanese profiles exist in the base Profiles class
echo "Verifying initial data state..."
JAPANESE_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Profiles WHERE Nationality='Japanese' AND @class='Profiles'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result', [{}])[0].get('count', 0))")

echo "Found $JAPANESE_COUNT Japanese profiles in 'Profiles' class."

if [ "$JAPANESE_COUNT" -lt 1 ]; then
    echo "Error: Initial data missing. Re-seeding..."
    # Force insert of required test profiles
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='yuki.tanaka@example.com', Name='Yuki', Surname='Tanaka', Gender='Female', Birthday='1995-04-12', Nationality='Japanese'" > /dev/null
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='kai.yamamoto@example.com', Name='Kai', Surname='Yamamoto', Gender='Male', Birthday='1996-08-16', Nationality='Japanese'" > /dev/null
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="