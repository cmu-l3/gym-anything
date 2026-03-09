#!/bin/bash
echo "=== Exporting configure_custom_log_format results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Generate Traffic for Functional Verification
# We make a request. If the config is correct, this request will have the latency at the end of the line in the log.
echo "Generating traffic to test logging..."
curl -s "http://acmecorp.test/latency_test_$(date +%s)" > /dev/null
sleep 2

# 2. Capture Configuration Files
# Global Config
GLOBAL_CONFIG_CONTENT=""
if [ -f /etc/apache2/apache2.conf ]; then
    # We only care about the LogFormat lines to keep JSON small
    GLOBAL_CONFIG_CONTENT=$(grep "LogFormat" /etc/apache2/apache2.conf | base64 -w 0)
fi

# Virtual Host Config
VHOST_CONFIG_PATH=$(find /etc/apache2/sites-enabled -name "*acmecorp.test.conf" | head -1)
VHOST_CONFIG_CONTENT=""
if [ -f "$VHOST_CONFIG_PATH" ]; then
    VHOST_CONFIG_CONTENT=$(cat "$VHOST_CONFIG_PATH" | base64 -w 0)
fi

# 3. Capture Log Content
# We grab the last 5 lines of the access log
LOG_FILE="/var/log/virtualmin/acmecorp.test_access_log"
LOG_TAIL=""
if [ -f "$LOG_FILE" ]; then
    LOG_TAIL=$(tail -n 5 "$LOG_FILE" | base64 -w 0)
fi

# 4. Check Apache Status
APACHE_RUNNING="false"
if systemctl is-active --quiet apache2; then
    APACHE_RUNNING="true"
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "apache_running": $APACHE_RUNNING,
    "global_config_b64": "$GLOBAL_CONFIG_CONTENT",
    "vhost_config_b64": "$VHOST_CONFIG_CONTENT",
    "log_tail_b64": "$LOG_TAIL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="