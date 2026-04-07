#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current settings from Redmine database via Rails runner
echo "Querying Redmine settings..."
SETTINGS_JSON_RAW=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "
    puts ({
      app_title: Setting.app_title,
      welcome_text: Setting.welcome_text,
      date_format: Setting.date_format,
      time_format: Setting.time_format,
      user_format: Setting.user_format
    }.to_json)
  " | grep "^{")

# Fallback if query failed
if [ -z "$SETTINGS_JSON_RAW" ]; then
  SETTINGS_JSON_RAW="{}"
fi

# Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "current_settings": $SETTINGS_JSON_RAW
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="