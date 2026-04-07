#!/bin/bash
echo "=== Setting up grant_joint_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for MySQL to be ready
until docker exec opencad-db mysqladmin ping -h localhost -u root -prootpass 2>/dev/null; do
    echo "Waiting for DB..."
    sleep 2
done

# RESET STATE: Ensure Dispatch Officer (ID 3) has ONLY Communications (ID 1)
echo "Resetting user permissions for User ID 3..."
# Clear existing
opencad_db_query "DELETE FROM user_departments WHERE user_id = 3;"
# Insert only Communications
opencad_db_query "INSERT INTO user_departments (user_id, department_id) VALUES (3, 1);"

# Record initial state for verification
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id = 3")
echo "$INITIAL_COUNT" > /tmp/initial_dept_count.txt
echo "Initial department count for User 3: $INITIAL_COUNT"

# Ensure OpenCAD is accessible
if ! pgrep -f "apache2" > /dev/null; then
    echo "Ensuring OpenCAD containers are up..."
    cd /home/ga/opencad
    docker-compose up -d
    sleep 5
fi

# Restart Firefox to ensure clean session
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' &"
sleep 10

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="