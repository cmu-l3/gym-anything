#!/bin/bash
set -e
echo "=== Setting up go_on_duty_fire task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Grant Fire Department (ID 6) access to Admin User (ID 2)
# Check if already exists to avoid dupes
HAS_ACCESS=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id=2 AND department_id=6")
if [ "$HAS_ACCESS" -eq 0 ]; then
    echo "Granting Fire access to Admin..."
    opencad_db_query "INSERT INTO user_departments (user_id, department_id) VALUES (2, 6);"
fi

# 2. Ensure Admin is NOT currently on duty (Clear from units table)
echo "Clearing any existing active unit session..."
opencad_db_query "DELETE FROM units WHERE user_id = 2;"

# 3. Launch Firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/initial_state.png

echo "=== Task setup complete ==="