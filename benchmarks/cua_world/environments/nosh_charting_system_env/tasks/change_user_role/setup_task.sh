#!/bin/bash
set -e
echo "=== Setting up change_user_role task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database is Ready
echo "Waiting for database..."
until docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent; do
    echo "Waiting for database connection..."
    sleep 2
done

# 3. Reset State: Ensure demo_provider exists and is a Provider (group_id=2)
echo "Resetting demo_provider role..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "UPDATE users SET group_id=2 WHERE username='demo_provider';"

# Verify reset
INITIAL_GROUP=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT group_id FROM users WHERE username='demo_provider'")

echo "$INITIAL_GROUP" > /tmp/initial_group_id.txt
echo "Initial group ID for demo_provider: $INITIAL_GROUP"

if [ "$INITIAL_GROUP" != "2" ]; then
    echo "ERROR: Failed to reset user role. Group ID is $INITIAL_GROUP"
    # Attempt to re-create if missing (fallback)
    # This relies on the provider existing from env setup, but if missing:
    # We exit distinctively so the framework knows setup failed
    exit 1
fi

# 4. Prepare Browser
# Kill existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Launch Firefox to Login Page
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"

# 5. Window Management
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox" | awk '{print $1}' | head -n 1)
        
        # Maximize
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
        
        # Focus
        DISPLAY=:1 wmctrl -ia "$WID"
        break
    fi
    sleep 1
done

# 6. Capture Initial State Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="