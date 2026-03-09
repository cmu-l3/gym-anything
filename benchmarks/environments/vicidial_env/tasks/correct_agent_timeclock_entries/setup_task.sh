#!/bin/bash
set -e
echo "=== Setting up correct_agent_timeclock_entries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for Vicidial MySQL..."
for i in {1..60}; do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# Define SQL commands to setup the scenario
# 1. Clean up user 7001 and logs
# 2. Create user 7001
# 3. Insert specific timeclock logs

SETUP_SQL=$(cat <<EOF
DELETE FROM vicidial_users WHERE user='7001';
DELETE FROM vicidial_timeclock_log WHERE user='7001';

INSERT INTO vicidial_users (user, pass, full_name, user_level, user_group, active, modify_timeclock_log) 
VALUES ('7001', '1234', 'James Lankford', 1, 'AGENTS', 'Y', '0');

-- Feb 24: Login 09:00, Logout 09:15 (Wrong)
INSERT INTO vicidial_timeclock_log (event, user, user_group, event_epoch, event_date, ip_address) 
VALUES ('LOGIN', '7001', 'AGENTS', 1771923600, '2026-02-24 09:00:00', '192.168.1.50');
INSERT INTO vicidial_timeclock_log (event, user, user_group, event_epoch, event_date, ip_address) 
VALUES ('LOGOUT', '7001', 'AGENTS', 1771924500, '2026-02-24 09:15:00', '192.168.1.50');

-- Feb 25: Login 09:30 (Wrong), Logout 17:00
INSERT INTO vicidial_timeclock_log (event, user, user_group, event_epoch, event_date, ip_address) 
VALUES ('LOGIN', '7001', 'AGENTS', 1772011800, '2026-02-25 09:30:00', '192.168.1.50');
INSERT INTO vicidial_timeclock_log (event, user, user_group, event_epoch, event_date, ip_address) 
VALUES ('LOGOUT', '7001', 'AGENTS', 1772038800, '2026-02-25 17:00:00', '192.168.1.50');

-- Ensure admin 6666 has permissions
UPDATE vicidial_users SET modify_timeclock_log='1' WHERE user='6666';
EOF
)

# Execute SQL setup
echo "Executing DB setup..."
docker exec -i vicidial mysql -ucron -p1234 -D asterisk <<< "$SETUP_SQL"

# Start Firefox and log in
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Pre-auth via URL or manual typing handled by the user/agent usually, 
# but for setup we'll start at the login page or main admin page.
# Since Vicidial often uses Basic Auth or Form Auth depending on setup,
# we'll load the admin page. The agent handles the interaction.
# However, to be helpful, we can try to pre-load if credentials are known/saved,
# but per instructions, we just ensure the app is open.
# The environment `vicidial_admin_url` usually includes auth or we let agent handle it.
# We'll open the users page directly to save a click if auth passes, or login page.

VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "Firefox" 30
maximize_active_window

# Dismiss any potential restore session dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="