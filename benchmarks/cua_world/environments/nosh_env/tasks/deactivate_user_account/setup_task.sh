#!/bin/bash
# Setup script for deactivate_user_account task

echo "=== Setting up Deactivate User Account Task ==="

# Source shared utilities if available, otherwise define basics
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure the target user 'jdoe' exists and is ACTIVE
echo "Creating/Resetting target user 'jdoe'..."

# Generate a password hash (using the one from setup_nosh.sh for simplicity or generating new)
# Default hash for 'User1234!' or similar. Using the Admin hash pattern for convenience as it's just a setup.
PASS_HASH='$2y$10$6tBChBBTMVa1E3iqLI9.u.vT2Uyunn6F.jrEqN.9YLq/f.TMzI3.'

# ID 999 to avoid conflicts with standard users
SQL_CMD="INSERT INTO users (id, username, email, displayname, firstname, lastname, password, group_id, active, practice_id) VALUES (999, 'jdoe', 'jdoe@hillsidefm.local', 'John Doe', 'John', 'Doe', '${PASS_HASH}', 3, 1, 1) ON DUPLICATE KEY UPDATE active=1, displayname='John Doe';"

docker exec nosh-db mysql -uroot -prootpassword nosh -e "$SQL_CMD"

# Verify user was created/reset
USER_CHECK=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT active FROM users WHERE username='jdoe'")
echo "User 'jdoe' active status: $USER_CHECK"

# 3. Ensure Firefox is running and logged in as Admin
# We use the standard setup pattern to ensure the agent starts inside the app
echo "Ensuring Firefox is running..."
NOSH_URL="http://localhost/login"

# Kill existing firefox to ensure clean state if needed, or check if running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Launch with specific profile if available
    if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/nosh.profile" ]; then
        PROFILE_PATH="/home/ga/snap/firefox/common/.mozilla/firefox/nosh.profile"
        su - ga -c "DISPLAY=:1 /snap/bin/firefox --profile '$PROFILE_PATH' '$NOSH_URL' > /dev/null 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 firefox '$NOSH_URL' > /dev/null 2>&1 &"
    fi
    sleep 10
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 4. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="