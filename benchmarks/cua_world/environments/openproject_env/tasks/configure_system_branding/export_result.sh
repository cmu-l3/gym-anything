#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenProject Settings via Rails Runner
# We verify: app_title, welcome_text, date_format, start_of_week
# Note: start_of_week stores '1' for Monday, '7' for Sunday
echo "Querying system settings..."

RUBY_SCRIPT="
require 'json'
begin
  settings = {
    'app_title' => Setting.app_title,
    'welcome_text' => Setting.welcome_text,
    'date_format' => Setting.date_format,
    'start_of_week' => Setting.start_of_week
  }
  puts JSON.generate(settings)
rescue => e
  puts JSON.generate({'error' => e.message})
end
"

# Execute in container and capture output
SETTINGS_JSON=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_SCRIPT\"" 2>/dev/null || echo "{\"error\": \"Docker execution failed\"}")

# Clean up any potential noise from rails runner output (sometimes it prints deprecation warnings)
# We look for the last line that looks like JSON
CLEAN_JSON=$(echo "$SETTINGS_JSON" | grep "^{.*}$" | tail -n 1)
if [ -z "$CLEAN_JSON" ]; then
    CLEAN_JSON="{\"error\": \"Failed to parse JSON output\", \"raw\": \"$SETTINGS_JSON\"}"
fi

# Create result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "settings": $CLEAN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="