#!/bin/bash
echo "=== Exporting disable_system_services results ==="

SERVICE_NAME="debug-logger"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Service Status
# is-active returns 0 if active, non-zero if inactive/failed
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ACTIVE_STATE="active"
else
    ACTIVE_STATE="inactive"
fi

# 2. Check Enable Status
# is-enabled returns 0 if enabled, non-zero if disabled
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    UNIT_STATE="enabled"
else
    UNIT_STATE="disabled"
fi

# 3. Check if service file still exists (anti-gaming: verify they didn't delete it)
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    FILE_EXISTS="true"
else
    FILE_EXISTS="false"
fi

# 4. Check critical services (safety check)
CRITICAL_SERVICES_OK="true"
for svc in webmin apache2 mariadb; do
    if ! systemctl is-active --quiet "$svc"; then
        echo "WARNING: Critical service $svc is not running!"
        CRITICAL_SERVICES_OK="false"
    fi
done

# 5. Check Log File (proof it ran)
LOG_SIZE=$(stat -c%s /tmp/debug-logger.log 2>/dev/null || echo "0")

# Create JSON result
cat > "$RESULT_FILE" <<EOF
{
    "service_name": "$SERVICE_NAME",
    "final_active_state": "$ACTIVE_STATE",
    "final_unit_state": "$UNIT_STATE",
    "service_file_exists": $FILE_EXISTS,
    "critical_services_ok": $CRITICAL_SERVICES_OK,
    "log_file_size": $LOG_SIZE,
    "timestamp": $(date +%s)
}
EOF

# Set permissions so python verifier can read it
chmod 644 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"