#!/bin/bash
# Setup: create_user_account task
# Ensures user 'ariviera' and person 'Alice Riviera' do NOT exist.

echo "=== Setting up create_user_account task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_timestamp

# 2. Cleanup: Remove existing user 'ariviera' if present to ensure clean state
#    We use the REST API to find and purge/retire.
echo "Checking for existing user 'ariviera'..."
USER_UUID=$(omrs_get "/user?q=ariviera&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -n "$USER_UUID" ]; then
    echo "Found existing user $USER_UUID. Deleting..."
    omrs_delete "/user/$USER_UUID?purge=true" > /dev/null || true
    # If purge fails (common due to constraints), try to just retire
    omrs_delete "/user/$USER_UUID" > /dev/null || true
fi

# 3. Cleanup: Remove existing person 'Alice Riviera'
echo "Checking for existing person 'Alice Riviera'..."
PERSON_UUID=$(omrs_get "/person?q=Alice+Riviera&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -n "$PERSON_UUID" ]; then
    echo "Found existing person $PERSON_UUID. Deleting..."
    omrs_delete "/person/$PERSON_UUID?purge=true" > /dev/null || true
    omrs_delete "/person/$PERSON_UUID" > /dev/null || true
fi

# 4. Record initial user count (for sanity check)
INITIAL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_user_count

# 5. Open Firefox to the Home Page (Admin dashboard)
#    We start at the home page so the agent has to find the Admin section.
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== create_user_account task setup complete ==="
echo ""
echo "TASK: Create User Account"
echo "  Name:     Alice Riviera"
echo "  Username: ariviera"
echo "  Role:     Nurse"
echo "  Password: Nurse123!"
echo ""