#!/bin/bash
echo "=== Exporting Configure User Custom Field Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ruby script to inspect the database state
# We output a JSON object directly from Ruby to avoid parsing complex text in bash
RUBY_SCRIPT=$(cat <<EOF
require 'json'

result = {
  field_exists: false,
  field_type: nil,
  field_format: nil,
  field_created_at: 0,
  user_found: false,
  user_value: nil
}

begin
  # Check for Custom Field
  cf = CustomField.find_by(name: 'Employee ID')
  
  if cf
    result[:field_exists] = true
    result[:field_type] = cf.type.to_s
    result[:field_format] = cf.field_format
    result[:field_created_at] = cf.created_at.to_i
    
    # Check User Value
    u = User.find_by(login: 'alice.johnson')
    if u
      result[:user_found] = true
      # custom_value_for returns a CustomValue object or nil
      cv = u.custom_value_for(cf)
      result[:user_value] = cv ? cv.value : nil
    end
  end
rescue => e
  result[:error] = e.message
end

puts result.to_json
EOF
)

# Execute Ruby script inside the container
echo "Querying OpenProject database..."
DB_RESULT=$(op_rails "$RUBY_SCRIPT")

# Clean up output (sometimes Rails runner outputs deprecation warnings or logs)
# We look for the JSON line which starts with "{"
JSON_OUTPUT=$(echo "$DB_RESULT" | grep "^{" | head -n 1)

if [ -z "$JSON_OUTPUT" ]; then
    echo "WARNING: Failed to capture JSON output from Rails runner"
    JSON_OUTPUT="{}"
    echo "Raw Output: $DB_RESULT"
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "db_state": $JSON_OUTPUT,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="