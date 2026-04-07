#!/bin/bash
echo "=== Setting up reactivate_suspended_user task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker containers are running
cd /home/ga/opencad
docker-compose up -d 2>/dev/null || true
sleep 5

# Wait for MySQL
echo "Waiting for MySQL..."
for i in {1..30}; do
    if docker exec opencad-db mysqladmin ping -h localhost -u root -prootpass 2>/dev/null; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
done
sleep 5

# Ensure James Rodriguez is in a clearly SUSPENDED state
# Set suspend_reason to distinguish from merely unapproved/pending users
# We also ensure he has a temp department assignment so he CAN be approved
echo "=== Configuring James Rodriguez as suspended ==="
docker exec opencad-db mysql -u root -prootpass opencad -e "
UPDATE users SET approved = 0, suspend_reason = 'Failed to complete mandatory quarterly safety compliance training'
WHERE email = 'james.rodriguez@opencad.local';

INSERT IGNORE INTO user_departments_temp (user_id, department_id)
SELECT id, 5 FROM users WHERE email = 'james.rodriguez@opencad.local';
" 2>/dev/null || true

# Ensure Sarah Mitchell is PENDING (approved=0) but NOT suspended
docker exec opencad-db mysql -u root -prootpass opencad -e "
UPDATE users SET approved = 0, suspend_reason = ''
WHERE email = 'sarah.mitchell@opencad.local';
" 2>/dev/null || true

# Ensure Admin and Dispatch are ACTIVE
docker exec opencad-db mysql -u root -prootpass opencad -e "
UPDATE users SET approved = 1 WHERE email IN ('admin@opencad.local', 'dispatch@opencad.local');
" 2>/dev/null || true

# Record initial states for verification
JAMES_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email = 'james.rodriguez@opencad.local'")
echo "$JAMES_APPROVED" > /tmp/james_initial_approved.txt

ADMIN_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email = 'admin@opencad.local'")
echo "$ADMIN_APPROVED" > /tmp/admin_initial_approved.txt

DISPATCH_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email = 'dispatch@opencad.local'")
echo "$DISPATCH_APPROVED" > /tmp/dispatch_initial_approved.txt

SARAH_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email = 'sarah.mitchell@opencad.local'")
echo "$SARAH_APPROVED" > /tmp/sarah_initial_approved.txt

echo "Initial states recorded:"
echo "  James Rodriguez approved: $JAMES_APPROVED"
echo "  Admin User approved: $ADMIN_APPROVED"
echo "  Sarah Mitchell approved: $SARAH_APPROVED"

# Kill any existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to OpenCAD login page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox --no-remote http://localhost 2>/dev/null &"
sleep 10

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|mozilla|opencad|localhost"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="