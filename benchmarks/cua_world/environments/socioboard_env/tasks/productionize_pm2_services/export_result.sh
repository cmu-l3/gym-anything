#!/bin/bash
echo "=== Exporting productionize_pm2_services result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SYSTEMD_ENABLED="false"
DUMP_EXISTS="false"
DUMP_MTIME="0"
DUMP_PROCESS_COUNT="0"
MODULE_RETAIN=""
MODULE_COMPRESS=""
SYS_LOGROTATE_CONTENT=""

# 1. Check if pm2-root service is enabled
if systemctl is-enabled pm2-root.service >/dev/null 2>&1; then
    SYSTEMD_ENABLED="true"
fi

# 2. Check PM2 dump file for root
if sudo test -f /root/.pm2/dump.pm2; then
    DUMP_EXISTS="true"
    DUMP_MTIME=$(sudo stat -c %Y /root/.pm2/dump.pm2 2>/dev/null || echo "0")
    # Parse the dump file to see how many processes were saved
    DUMP_PROCESS_COUNT=$(sudo cat /root/.pm2/dump.pm2 | jq '. | length' 2>/dev/null || echo "0")
fi

# 3. Check pm2-logrotate module configuration
if sudo test -f /root/.pm2/module_conf.json; then
    MODULE_RETAIN=$(sudo cat /root/.pm2/module_conf.json | jq -r '."pm2-logrotate".retain // empty' 2>/dev/null)
    MODULE_COMPRESS=$(sudo cat /root/.pm2/module_conf.json | jq -r '."pm2-logrotate".compress // empty' 2>/dev/null)
fi

# 4. Check system logrotate configuration (if they chose this route)
# We concatenate all files in /etc/logrotate.d/ that contain ".pm2" or "pm2"
SYS_LOGROTATE_CONTENT=$(sudo grep -irE "pm2" /etc/logrotate.d/ 2>/dev/null || true)

# Create JSON report
TEMP_JSON=$(mktemp /tmp/pm2_result.XXXXXX.json)
sudo bash -c "cat > $TEMP_JSON << 'EOF'
{
  \"task_start_time\": $TASK_START,
  \"systemd_enabled\": $SYSTEMD_ENABLED,
  \"dump_exists\": $DUMP_EXISTS,
  \"dump_mtime\": $DUMP_MTIME,
  \"dump_process_count\": $DUMP_PROCESS_COUNT,
  \"module_retain\": \"$MODULE_RETAIN\",
  \"module_compress\": \"$MODULE_COMPRESS\",
  \"sys_logrotate_content\": $(echo "$SYS_LOGROTATE_CONTENT" | jq -R -s '.')
}
EOF"

# Move to final location with proper permissions so the verifier can read it
sudo rm -f /tmp/task_result.json
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Exported results to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="