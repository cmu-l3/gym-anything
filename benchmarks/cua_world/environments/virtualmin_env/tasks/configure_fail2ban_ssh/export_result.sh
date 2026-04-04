#!/bin/bash
echo "=== Exporting configure_fail2ban_ssh result ==="

# Record execution time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Service Status
SERVICE_ACTIVE="false"
if systemctl is-active --quiet fail2ban; then
    SERVICE_ACTIVE="true"
fi

# 2. Check Runtime Configuration (The most important check)
# We use fail2ban-client to see what the RUNNING daemon thinks.
# If the agent edited the file but didn't restart, this will fail (correctly).
RUNTIME_MAX_RETRY="0"
RUNTIME_BAN_TIME="0"
JAIL_ACTIVE="false"

if [ "$SERVICE_ACTIVE" = "true" ]; then
    # Check if jail is running
    if fail2ban-client status sshd > /dev/null 2>&1; then
        JAIL_ACTIVE="true"
        RUNTIME_MAX_RETRY=$(fail2ban-client get sshd maxretry 2>/dev/null || echo "0")
        RUNTIME_BAN_TIME=$(fail2ban-client get sshd bantime 2>/dev/null || echo "0")
    fi
fi

# 3. Check Configuration File (Secondary signal)
# Useful for partial credit or debugging if service failed to start
CONFIG_FILE_CONTENT=""
if [ -f /etc/fail2ban/jail.local ]; then
    CONFIG_FILE_CONTENT=$(cat /etc/fail2ban/jail.local | base64 -w 0)
elif [ -f /etc/fail2ban/jail.d/defaults-debian.conf ]; then
    CONFIG_FILE_CONTENT=$(cat /etc/fail2ban/jail.d/defaults-debian.conf | base64 -w 0)
fi

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_active": $SERVICE_ACTIVE,
    "jail_active": $JAIL_ACTIVE,
    "runtime_max_retry": $RUNTIME_MAX_RETRY,
    "runtime_ban_time": $RUNTIME_BAN_TIME,
    "config_file_b64": "$CONFIG_FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json