#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up schema_constraints task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

# Ensure demodb exists (it should be created by environment setup, but verify)
if ! orientdb_db_exists demodb; then
    echo "ERROR: demodb does not exist! Running setup..."
    # Fallback to creating it if missing (shouldn't happen in correct env)
    /workspace/scripts/setup_orientdb.sh
fi

# Reset any previously set constraints to ensure clean starting state
echo "Resetting existing constraints to ensure clean state..."

# Helper to run safe SQL (ignoring errors if property doesn't exist yet)
safe_sql() {
    orientdb_sql "demodb" "$1" > /dev/null 2>&1 || true
}

# Hotels.Name
safe_sql "ALTER PROPERTY Hotels.Name MANDATORY false"
safe_sql "ALTER PROPERTY Hotels.Name NOTNULL false"

# Hotels.Stars
safe_sql "ALTER PROPERTY Hotels.Stars MIN null"
safe_sql "ALTER PROPERTY Hotels.Stars MAX null"

# Profiles.Email
safe_sql "ALTER PROPERTY Profiles.Email MANDATORY false"
safe_sql "ALTER PROPERTY Profiles.Email NOTNULL false"

# Orders.Price
safe_sql "ALTER PROPERTY Orders.Price MIN null"

# Restaurants.Name
safe_sql "ALTER PROPERTY Restaurants.Name MANDATORY false"
safe_sql "ALTER PROPERTY Restaurants.Name NOTNULL false"

# Reviews STRICTMODE
safe_sql "ALTER CLASS Reviews STRICTMODE false"

echo "Constraints reset complete."

# Record initial schema state for anti-gaming comparison
# We save the raw JSON schema
echo "Recording initial schema state..."
curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" > /tmp/initial_schema.json 2>/dev/null || true

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
launch_firefox "http://localhost:2480/studio/index.html" 10

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="