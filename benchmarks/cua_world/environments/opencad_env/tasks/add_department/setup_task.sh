#!/bin/bash
echo "=== Setting up add_department task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous attempts (ensure clean state)
# Remove 'Mine Safety Division' if it already exists to ensure the agent actually creates it
echo "Checking for existing department..."
EXISTING_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE LOWER(department_name) LIKE '%mine safety%' LIMIT 1")
if [ -n "$EXISTING_ID" ]; then
    echo "Removing pre-existing Mine Safety department (ID: $EXISTING_ID)..."
    opencad_db_query "DELETE FROM departments WHERE department_id = $EXISTING_ID"
fi

# 2. Record initial department count
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM departments")
echo "${INITIAL_COUNT:-0}" | sudo tee /tmp/initial_dept_count > /dev/null
sudo chmod 666 /tmp/initial_dept_count
echo "Initial department count: $INITIAL_COUNT"

# 3. Ensure Admin user has Data Manager permissions (privilege 3)
echo "Ensuring admin privileges..."
opencad_db_query "UPDATE users SET admin_privilege=3 WHERE email='admin@opencad.local'"

# 4. Prepare Browser
# Remove Firefox profile locks and restart
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Open login page
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/login.php" &
sleep 10

# 5. UI Setup
# Dismiss potential popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 6. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 7. Initial evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="