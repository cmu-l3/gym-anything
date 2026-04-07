#!/bin/bash
echo "=== Setting up edit_department task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify the target department exists and record its initial state
echo "=== Verifying initial department state ==="
# Look for San Andreas Highway Patrol or similar
DEPT_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_name LIKE '%Highway Patrol%' LIMIT 1")

if [ -z "$DEPT_ID" ]; then
    echo "WARNING: Highway Patrol department not found by name. Checking by short name 'SAHP'..."
    DEPT_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_short_name = 'SAHP' LIMIT 1")
fi

if [ -z "$DEPT_ID" ]; then
    echo "CRITICAL ERROR: Cannot find target department 'San Andreas Highway Patrol' or 'SAHP'. Task may be impossible."
    # We don't exit 1 because the agent might still be able to do something if the state is weird, 
    # but verification will likely fail.
else
    # Record initial state for verification
    DEPT_NAME=$(opencad_db_query "SELECT department_name FROM departments WHERE department_id = $DEPT_ID")
    DEPT_SHORT=$(opencad_db_query "SELECT department_short_name FROM departments WHERE department_id = $DEPT_ID")
    ASSOC_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE department_id = $DEPT_ID")

    echo "$DEPT_ID" > /tmp/initial_dept_id.txt
    echo "$DEPT_NAME" > /tmp/initial_dept_name.txt
    echo "$DEPT_SHORT" > /tmp/initial_dept_short.txt
    echo "$ASSOC_COUNT" > /tmp/initial_assoc_count.txt

    echo "Target department found: ID=$DEPT_ID, Name='$DEPT_NAME', Short='$DEPT_SHORT', Associations=$ASSOC_COUNT"
fi

# Ensure Firefox is running with OpenCAD
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost &" > /dev/null 2>&1 &
    sleep 8
else
    # Navigate to login page
    su - ga -c "DISPLAY=:1 firefox http://localhost &" > /dev/null 2>&1 &
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|mozilla|opencad|localhost"; then
        echo "Firefox window found"
        break
    fi
    sleep 1
done

# Maximize and focus Firefox
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="