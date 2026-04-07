#!/bin/bash
# Export script for configure_system_default_columns task

source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_system_default_columns results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the actual system setting from the database via Rails
# We need to get:
# - The current list of columns
# - The updated_at timestamp of the setting to ensure it was changed NOW
echo "Querying OpenProject settings..."

# Ruby script to extract setting details
RUBY_SCRIPT="
require 'json'
begin
  # The setting key is 'work_package_list_default_columns'
  # It is serialized, so .value returns the array
  s = Setting.find_by(name: 'work_package_list_default_columns')
  if s
    result = {
      exists: true,
      value: s.value,
      updated_at: s.updated_on.to_i
    }
  else
    result = {
      exists: false,
      value: [],
      updated_at: 0
    }
  end
  puts result.to_json
rescue => e
  puts({ error: e.message }.to_json)
end
"

# Execute inside container
SETTING_JSON=$(op_rails "$RUBY_SCRIPT")

# Clean up any rails runner noise (sometimes it outputs deprecation warnings)
# We look for the last line that looks like JSON
CLEAN_JSON=$(echo "$SETTING_JSON" | grep "^{" | tail -n 1)

if [ -z "$CLEAN_JSON" ]; then
    CLEAN_JSON='{"error": "Failed to parse Rails output"}'
fi

# 3. Create the result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "setting_data": $CLEAN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="