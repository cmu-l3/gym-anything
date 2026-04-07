#!/bin/bash
echo "=== Setting up enforce_part11_security_baselines task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenClinica to be ready to ensure database is fully up
echo "Waiting for OpenClinica to be ready..."
verify_openclinica_ready 120

# Ensure mrivera exists and has a recent password timestamp (not expired)
echo "Setting up compromised user account (mrivera)..."
MRIVERA_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'mrivera'" 2>/dev/null || echo "0")
if [ "${MRIVERA_EXISTS:-0}" = "0" ]; then
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created, passwd_timestamp)
              VALUES ('mrivera', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Michael', 'Rivera', 'mrivera@clinical.org', 1, 1, NOW(), NOW())" 2>/dev/null || true
else
    oc_query "UPDATE user_account SET passwd_timestamp = NOW() WHERE user_name = 'mrivera'" 2>/dev/null || true
fi

# Revert datainfo.properties to insecure defaults to ensure a clean slate
echo "Resetting datainfo.properties to default vulnerable state..."
docker exec oc-app sed -i 's/^passwd\.length\.min=.*/passwd.length.min=8/' /usr/local/tomcat/webapps/OpenClinica/WEB-INF/classes/datainfo.properties 2>/dev/null || true
docker exec oc-app sed -i 's/^passwd\.expiration\.days=.*/passwd.expiration.days=365/' /usr/local/tomcat/webapps/OpenClinica/WEB-INF/classes/datainfo.properties 2>/dev/null || true
docker exec oc-app sed -i 's/^support\.email=.*/support.email=admin@localhost/' /usr/local/tomcat/webapps/OpenClinica/WEB-INF/classes/datainfo.properties 2>/dev/null || true

# Record the initial Docker container start time (to verify agent restarts it)
docker inspect -f '{{.State.StartedAt}}' oc-app > /tmp/container_start_time.txt

# Launch Firefox in the background just to provide visual context
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/OpenClinica/MainMenu &"
    sleep 5
fi

# Maximize Firefox if it's open
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="