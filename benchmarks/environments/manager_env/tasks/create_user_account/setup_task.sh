#!/bin/bash
set -e

echo "=== Setting up create_user_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
ensure_manager_running

# ---------------------------------------------------------------------------
# Clean State: Ensure 'sjohnson' does NOT exist
# ---------------------------------------------------------------------------
echo "Ensuring clean state (removing sjohnson if exists)..."
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
rm -f "$COOKIE_FILE"

# Login as administrator
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "http://localhost:8080/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

# Check if user exists
USERS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "http://localhost:8080/users" -L 2>/dev/null || echo "")

if echo "$USERS_PAGE" | grep -qi "sjohnson"; then
    echo "User sjohnson found, attempting to delete..."
    
    # Python script to extract the specific delete URL or Key for sjohnson
    # Manager.io typically uses a key in the URL like /user-form?key=... or /delete-user?key=...
    # We'll try to find the key associated with the row containing "sjohnson"
    USER_KEY=$(echo "$USERS_PAGE" | python3 -c "
import sys, re
html = sys.stdin.read()
# Find link that looks like user-form?Key=... inside a row with sjohnson
# Then construct delete link
m = re.search(r'user-form\?([^\"&]+)[^<]*sjohnson', html, re.IGNORECASE)
if m:
    print(m.group(1))
" 2>/dev/null || echo "")

    if [ -n "$USER_KEY" ]; then
        # Manager usually requires a POST to delete, often with a confirmation or just the key
        # Tricky part: automation of deletion without UI. 
        # Attempting direct POST to delete endpoint if standard convention applies
        # If strictly idempotent setup is needed, we rely on the container reset. 
        # Since we can't easily delete via simple curl without knowing the exact form token structure,
        # we will log this. Ideally, the container starts fresh.
        echo "WARNING: Could not automatically delete existing user (complex ID). Task assumes fresh container."
    fi
else
    echo "User sjohnson does not exist (clean state confirmed)."
fi

# Record initial user count for verification comparison
INITIAL_USER_COUNT=$(echo "$USERS_PAGE" | grep -c "user-form" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# ---------------------------------------------------------------------------
# Browser Setup
# ---------------------------------------------------------------------------
# Open Manager at the Business Summary page (inside the business)
# This forces the agent to navigate OUT to the server level, which is part of the challenge.
echo "Opening Manager.io at Northwind Traders Summary..."
open_manager_at "summary"

# Capture initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="