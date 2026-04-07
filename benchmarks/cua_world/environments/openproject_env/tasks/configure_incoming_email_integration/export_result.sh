#!/bin/bash
echo "=== Exporting configure_incoming_email_integration result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current settings from OpenProject via Rails runner
# We output JSON directly from Ruby to avoid parsing issues
echo "Querying OpenProject settings..."
SETTINGS_JSON=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"
require 'json'
result = {
  enabled: Setting.mail_handler_enable_incoming_emails? ? true : false,
  api_key: Setting.mail_handler_api_key.to_s,
  delimiters: Setting.mail_handler_body_delimiters.to_s,
  updated_on: Setting.where(name: 'mail_handler_api_key').pluck(:updated_on).first
}
puts JSON.generate(result)
\" 2>/dev/null")

# If command failed or returned empty, use default JSON
if [ -z "$SETTINGS_JSON" ]; then
    SETTINGS_JSON='{"enabled": false, "api_key": "", "delimiters": "", "error": "Query failed"}'
fi

# Create final result JSON
# We embed the Rails output into our wrapper JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "settings": $SETTINGS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="