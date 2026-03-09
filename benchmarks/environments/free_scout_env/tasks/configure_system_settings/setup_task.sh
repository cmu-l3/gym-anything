#!/bin/bash
echo "=== Setting up configure_system_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ===== Record initial settings state =====
# We record this to verify the agent actually CHANGED something, preventing "do nothing" gaming
echo "Recording initial settings state..."

# Helper to get option value safely
get_option() {
    local name="$1"
    fs_query "SELECT value FROM options WHERE name='$name' LIMIT 1" 2>/dev/null || echo "DEFAULT_EMPTY"
}

INITIAL_COMPANY=$(get_option "company_name")
INITIAL_TIMEZONE=$(get_option "timezone")
INITIAL_TIMEFORMAT=$(get_option "time_format")

# Save to temp files for export script to compare later
echo "$INITIAL_COMPANY" > /tmp/initial_company_name.txt
echo "$INITIAL_TIMEZONE" > /tmp/initial_timezone.txt
echo "$INITIAL_TIMEFORMAT" > /tmp/initial_time_format.txt

echo "Initial state recorded:"
echo "  Company: $INITIAL_COMPANY"
echo "  Timezone: $INITIAL_TIMEZONE"
echo "  Format: $INITIAL_TIMEFORMAT"

# ===== Ensure Application is Ready =====
# Ensure FreeScout containers are running
if ! docker ps | grep -q freescout-app; then
    echo "Starting FreeScout containers..."
    cd /home/ga/freescout
    docker-compose up -d
    sleep 20
fi

# Wait for FreeScout to be accessible
wait_for_freescout() {
    for i in {1..30}; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" | grep -q "200\|302"; then
            echo "FreeScout is ready"
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_for_freescout

# ===== Setup Browser =====
# Kill existing instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to login page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
sleep 8

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|freescout" 30; then
    echo "Firefox window detected"
    focus_firefox
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Ensure we are at login screen or dashboard
    ensure_logged_in
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="