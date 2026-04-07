#!/bin/bash
echo "=== Setting up revoke_department_access task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Prepare Database State
# We need to ensure James Rodriguez exists and has SPECIFIC department access (Police + Civilian)
echo "Configuring database state..."

# Get IDs (robust lookups)
JAMES_ID=$(opencad_db_query "SELECT id FROM users WHERE email='james.rodriguez@opencad.local' LIMIT 1")
POLICE_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_name='Police' LIMIT 1")
CIVILIAN_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_name='Civilian' LIMIT 1")

# Verify we have the IDs we need
if [ -z "$JAMES_ID" ] || [ -z "$POLICE_ID" ] || [ -z "$CIVILIAN_ID" ]; then
    echo "CRITICAL ERROR: Seed data missing. James: $JAMES_ID, Police: $POLICE_ID, Civilian: $CIVILIAN_ID"
    # Attempt to fix James if missing (basic recovery)
    if [ -z "$JAMES_ID" ]; then
         echo "Re-seeding James Rodriguez..."
         # This assumes the PHP hashing script in setup_opencad.sh logic, but for simplicity we skip complex recovery 
         # and fail loud if env is broken, or just exit.
         exit 1
    fi
fi

# Reset Department Access for James
# First, remove any existing links for him to ensure clean slate
opencad_db_query "DELETE FROM user_departments WHERE user_id=${JAMES_ID}"

# Insert the specific links we want: Police AND Civilian
opencad_db_query "INSERT INTO user_departments (user_id, department_id) VALUES (${JAMES_ID}, ${POLICE_ID})"
opencad_db_query "INSERT INTO user_departments (user_id, department_id) VALUES (${JAMES_ID}, ${CIVILIAN_ID})"

# Ensure James is Approved (Active)
opencad_db_query "UPDATE users SET approved=1 WHERE id=${JAMES_ID}"

echo "Database configured: James (ID $JAMES_ID) assigned to Police ($POLICE_ID) and Civilian ($CIVILIAN_ID)"

# 3. Setup Browser
# Kill existing firefox to ensure clean session state
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
sleep 2

# Launch Firefox
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 4. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="