#!/bin/bash
# Setup script for Send Provider Message task in OSCAR EMR

echo "=== Setting up Send Provider Message Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the recipient provider (Dr. James Wilson) exists
echo "Ensuring recipient Dr. James Wilson exists..."
# Check if exists first
WILSON_EXISTS=$(oscar_query "SELECT COUNT(*) FROM provider WHERE provider_no='100001'" || echo "0")
if [ "${WILSON_EXISTS:-0}" -eq 0 ]; then
    echo "Creating Dr. James Wilson (100001)..."
    oscar_query "INSERT INTO provider (provider_no, last_name, first_name, provider_type, sex, specialty, status) VALUES ('100001', 'Wilson', 'James', 'doctor', 'M', 'Cardiology', '1');" 2>/dev/null || true
    # Create security record just in case it's needed for lookup
    oscar_query "INSERT INTO security (security_no, user_name, password, provider_no, pin) VALUES (100001, 'wilsonj', '45-179-551441115-117798-30877213-3052-6889-30-60', '100001', '2234');" 2>/dev/null || true
else
    echo "Dr. James Wilson already exists."
fi

# 2. Record initial state for anti-gaming (Max Message ID)
# We will look for messages created AFTER this ID
MAX_MSG_ID=$(oscar_query "SELECT COALESCE(MAX(message_id), 0) FROM messagetbl" || echo "0")
echo "$MAX_MSG_ID" > /tmp/initial_max_msg_id
echo "Initial Max Message ID: $MAX_MSG_ID"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# 3. Ensure Firefox is open on the login page
ensure_firefox_on_oscar

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Send a message to Dr. James Wilson"
echo "Login: oscardoc / oscar / PIN: 1117"