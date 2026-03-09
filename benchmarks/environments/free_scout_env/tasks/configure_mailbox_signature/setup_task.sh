#!/bin/bash
set -e
echo "=== Setting up configure_mailbox_signature task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ===== Ensure FreeScout is running =====
cd /home/ga/freescout
docker-compose up -d 2>/dev/null || true
sleep 5

# Wait for FreeScout to be ready
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "FreeScout is ready (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for FreeScout... ($i/30, HTTP $HTTP_CODE)"
    sleep 5
done

# ===== Create the IT Support mailbox if it doesn't exist =====
echo "Ensuring IT Support mailbox exists..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@acmecorp.com")
echo "IT Support mailbox ID: $MAILBOX_ID"

if [ -z "$MAILBOX_ID" ] || [ "$MAILBOX_ID" = "0" ]; then
    echo "WARNING: Could not create mailbox via ORM, trying direct SQL..."
    fs_query "INSERT INTO mailboxes (name, email, created_at, updated_at) VALUES ('IT Support', 'itsupport@acmecorp.com', NOW(), NOW())" 2>/dev/null || true
    MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='itsupport@acmecorp.com' LIMIT 1" 2>/dev/null)
    echo "Mailbox ID via SQL: $MAILBOX_ID"
fi

# ===== Clear any existing signature to ensure clean state =====
echo "Clearing existing signature..."
if [ -n "$MAILBOX_ID" ] && [ "$MAILBOX_ID" != "0" ]; then
    fs_query "UPDATE mailboxes SET signature = NULL WHERE id = $MAILBOX_ID" 2>/dev/null || true
    
    # Record initial state
    INITIAL_SIG=$(fs_query "SELECT IFNULL(signature, 'NULL') FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null)
    echo "Initial signature state: $INITIAL_SIG"
    
    # Record the mailbox ID for export script
    echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt
else
    echo "ERROR: Failed to establish mailbox ID"
fi

# ===== Ensure Firefox is running =====
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    echo "Firefox already running"
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|FreeScout" 30 || echo "WARNING: Firefox window not detected"

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox
sleep 2

# Navigate to FreeScout login page
navigate_to_url "http://localhost:8080/login"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="