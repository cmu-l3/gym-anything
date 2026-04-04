#!/bin/bash
set -e
echo "=== Setting up audit_failed_login_attempt task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is running
if ! pgrep -f "freescout" > /dev/null && ! docker ps | grep -q freescout-app; then
    echo "Starting FreeScout..."
    /workspace/scripts/setup_freescout.sh
fi

# Wait for FreeScout to be responsive
echo "Waiting for FreeScout to be responsive..."
for i in {1..30}; do
    if curl -s http://localhost:8080/login | grep -q "FreeScout"; then
        break
    fi
    sleep 2
done

# Ensure the admin user exists (id 1 usually)
ADMIN_ID=$(fs_query "SELECT id FROM users WHERE email='admin@helpdesk.local' LIMIT 1")
if [ -z "$ADMIN_ID" ]; then
    echo "Creating admin user..."
    # This shouldn't happen in standard env, but fallback just in case
    fs_tinker "\$u = new \App\User; \$u->email = 'admin@helpdesk.local'; \$u->password = bcrypt('Admin123!'); \$u->role = 'admin'; \$u->first_name='Admin'; \$u->last_name='User'; \$u->save();"
fi

# Clean up previous attempts/artifacts
rm -f /home/ga/suspicious_ip.txt
rm -f /tmp/ground_truth_ip.txt

# Generate a verifiable "Failed Login" event
# We try to inject a specific IP via X-Forwarded-For.
# Even if FreeScout ignores it (due to Trusted Proxy settings), we will query the DB 
# to see what it *actually* recorded, ensuring ground truth is accurate.

TARGET_IP="203.0.113.88" # Distinctive IP
COOKIE_JAR="/tmp/cookies.txt"

echo "Generating failed login attempt..."

# 1. Get CSRF token
LOGIN_PAGE=$(curl -s -c $COOKIE_JAR http://localhost:8080/login)
CSRF_TOKEN=$(echo "$LOGIN_PAGE" | grep -oP 'name="_token" value="\K[^"]+' | head -1)

# 2. Perform failed login
# We use a User-Agent that we can optionally track, though we'll rely on timestamps/DB order
curl -s -b $COOKIE_JAR -c $COOKIE_JAR \
    -H "X-Forwarded-For: $TARGET_IP" \
    -H "User-Agent: SuspiciousBot/1.0" \
    -d "_token=$CSRF_TOKEN&email=admin@helpdesk.local&password=WRONG_PASSWORD_FAIL" \
    http://localhost:8080/login > /dev/null

rm -f $COOKIE_JAR

# Give DB a moment to sync
sleep 2

# EXTRACT GROUND TRUTH from Database
# We look for the most recent log entry. 
# FreeScout logs usually store the IP in the 'ip' column of the 'logs' table.
echo "Extracting ground truth IP from database..."

# Query: Get the IP of the most recent log entry created in the last minute
# We order by ID desc to get the one we just made.
GROUND_TRUTH_IP=$(fs_query "SELECT ip FROM logs ORDER BY id DESC LIMIT 1")

if [ -z "$GROUND_TRUTH_IP" ]; then
    echo "WARNING: Could not retrieve IP from logs table. Defaulting to empty."
else
    echo "Ground Truth IP recorded by system: '$GROUND_TRUTH_IP'"
fi

# Save ground truth to a hidden file for export_result.sh to read
echo "$GROUND_TRUTH_IP" > /tmp/ground_truth_ip.txt
chmod 600 /tmp/ground_truth_ip.txt

# Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|freescout" 30

# Focus and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="