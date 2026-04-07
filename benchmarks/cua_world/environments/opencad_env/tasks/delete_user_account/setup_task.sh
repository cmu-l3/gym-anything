#!/bin/bash
echo "=== Setting up delete_user_account task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the target user exists (Re-create if missing from previous runs)
# James Rodriguez: ID 5 (usually), Pending status
TARGET_EMAIL="james.rodriguez@opencad.local"
TARGET_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM users WHERE email='${TARGET_EMAIL}'")

if [ "$TARGET_EXISTS" -eq "0" ]; then
    echo "Restoring target user James Rodriguez..."
    # Insert user via PHP to ensure password hash is correct
    docker exec opencad-app php -r '
    $pdo = new PDO("mysql:host=opencad-db;dbname=opencad", "opencad", "opencadpass");
    $hash = password_hash("password123", PASSWORD_DEFAULT);
    $stmt = $pdo->prepare("INSERT INTO users (name, email, password, identifier, admin_privilege, supervisor_privilege, password_reset, approved) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute(["James Rodriguez", "james.rodriguez@opencad.local", $hash, "4B-22", 1, 0, 0, 0]);
    '
fi

# 2. Record Initial State for Verification
# Total count
INITIAL_COUNT=$(get_user_count)
echo "$INITIAL_COUNT" | sudo tee /tmp/initial_user_count > /dev/null
sudo chmod 666 /tmp/initial_user_count

# Verify 'Safe' users exist (Admin, Dispatch, Sarah)
SAFE_CHECK=$(opencad_db_query "SELECT COUNT(*) FROM users WHERE email IN ('admin@opencad.local', 'dispatch@opencad.local', 'sarah.mitchell@opencad.local')")
echo "$SAFE_CHECK" | sudo tee /tmp/initial_safe_users_count > /dev/null
sudo chmod 666 /tmp/initial_safe_users_count

# Record target user ID for specific tracking
TARGET_ID=$(opencad_db_query "SELECT id FROM users WHERE email='${TARGET_EMAIL}'")
echo "${TARGET_ID:-0}" | sudo tee /tmp/target_user_id > /dev/null
sudo chmod 666 /tmp/target_user_id

echo "Initial State: Total Users=$INITIAL_COUNT, Safe Users=$SAFE_CHECK, Target ID=$TARGET_ID"

# 3. Prepare Browser
# Remove Firefox profile locks and relaunch
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 4. Take initial evidence
take_screenshot /tmp/task_initial.png
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="