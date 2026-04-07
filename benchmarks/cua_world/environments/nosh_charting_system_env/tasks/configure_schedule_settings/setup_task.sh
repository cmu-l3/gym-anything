#!/bin/bash
set -e
echo "=== Setting up task: configure_schedule_settings ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Wait for NOSH to be responsive
NOSH_URL="http://localhost/login"
echo "Waiting for NOSH..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "$NOSH_URL" | grep -q "200\|302"; then
        echo "NOSH is ready."
        break
    fi
    sleep 2
done

# 3. Reset the database state (CRITICAL)
# Ensure the provider (id=2) has schedule_increment set to 20 initially
echo "Resetting provider schedule_increment to 20..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "UPDATE providers SET schedule_increment='20' WHERE id=2;"

# Verify reset was successful
INITIAL_VAL=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT schedule_increment FROM providers WHERE id=2;")

if [ "$INITIAL_VAL" != "20" ]; then
    echo "ERROR: Failed to set initial state. Current value: $INITIAL_VAL"
    exit 1
fi
echo "Initial schedule_increment: $INITIAL_VAL"

# 4. Launch Firefox to the login page
echo "Starting Firefox..."
# Kill any existing instances to ensure clean state
pkill -f firefox || true
sleep 1

# Start Firefox as user 'ga'
su - ga -c "DISPLAY=:1 firefox --new-window '$NOSH_URL' > /dev/null 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected."
        # Maximize
        DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        # Focus
        DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="