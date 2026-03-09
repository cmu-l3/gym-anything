#!/bin/bash
# Setup script for User Account Setup task

echo "=== Setting up User Account Setup Task ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Check if the target user already exists and delete if so (clean state)
echo "Checking for pre-existing fatmata.koroma user..."
EXISTING_USER=$(dhis2_api "users?filter=username:eq:fatmata.koroma&fields=id,username" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    users = d.get('users', [])
    if users:
        print(users[0].get('id', ''))
    else:
        print('')
except:
    print('')
" 2>/dev/null)

if [ -n "$EXISTING_USER" ]; then
    echo "Pre-existing user found (ID: $EXISTING_USER). Removing for clean task start..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/users/$EXISTING_USER" > /dev/null 2>&1 || \
        echo "Warning: Could not delete pre-existing user"
fi

# Record initial user count
echo "Recording initial user count..."
INITIAL_USER_COUNT=$(dhis2_api "users?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# Log available user roles for reference (agent must discover these)
echo "Available user roles in system:"
dhis2_api "userRoles?fields=id,displayName&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in d.get('userRoles', [])[:20]:
        print('  -', r.get('displayName', 'Unknown'))
except:
    print('  Could not list roles')
" 2>/dev/null || echo "  Could not retrieve roles"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Files Created ==="
echo "  /tmp/task_start_iso: $TASK_START"
echo "  /tmp/initial_user_count: $INITIAL_USER_COUNT"
echo ""
echo "=== User Account Setup Task Setup Complete ==="
