#!/bin/bash
# Setup script for Create Provider User task
# Records initial state and ensures OpenEMR is ready

echo "=== Setting up Create Provider User Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Expected username for the new provider
TARGET_USERNAME="jsmith_np"

# Record task start timestamp for anti-gaming verification
echo "Recording task start time..."
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START"

# Record initial user state for verification
echo "Recording initial user state..."

# Get current maximum user ID (new users will have higher IDs)
INITIAL_MAX_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COALESCE(MAX(id), 0) FROM users" 2>/dev/null || echo "0")
echo "$INITIAL_MAX_ID" > /tmp/initial_max_user_id
echo "Initial max user ID: $INITIAL_MAX_ID"

# Get total user count
INITIAL_USER_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# Get count of authorized users
INITIAL_AUTH_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users WHERE authorized=1" 2>/dev/null || echo "0")
echo "$INITIAL_AUTH_COUNT" > /tmp/initial_auth_user_count
echo "Initial authorized user count: $INITIAL_AUTH_COUNT"

# Remove any existing user with the target username (clean slate)
echo "Ensuring no existing user with username '$TARGET_USERNAME'..."
EXISTING_USER=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id FROM users WHERE username='$TARGET_USERNAME'" 2>/dev/null)
if [ -n "$EXISTING_USER" ]; then
    echo "Found existing user with target username (id=$EXISTING_USER), removing..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "DELETE FROM users WHERE username='$TARGET_USERNAME'" 2>/dev/null || true
    echo "Existing user removed"
else
    echo "No existing user with target username found (good)"
fi

# Verify admin user exists for login
echo "Verifying admin user exists..."
ADMIN_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id FROM users WHERE username='admin'" 2>/dev/null)
if [ -z "$ADMIN_CHECK" ]; then
    echo "WARNING: Admin user not found - login may fail"
else
    echo "Admin user verified (id=$ADMIN_CHECK)"
fi

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Create Provider User Task Setup Complete ==="
echo ""
echo "TASK: Create a new authorized provider user account"
echo ""
echo "Login Credentials:"
echo "  - Username: admin"
echo "  - Password: pass"
echo ""
echo "New Provider Details to Enter:"
echo "  - Username: jsmith_np"
echo "  - Password: NurseSmith2024!"
echo "  - First Name: Jennifer"
echo "  - Last Name: Smith"
echo "  - Middle Name: Marie"
echo "  - Credentials: NP"
echo "  - Federal Tax ID: 12-3456789"
echo "  - NPI: 1234567890"
echo "  - Authorized: YES (CRITICAL!)"
echo "  - Active: YES"
echo ""
echo "Navigation: Administration > Users > Add User"
echo ""