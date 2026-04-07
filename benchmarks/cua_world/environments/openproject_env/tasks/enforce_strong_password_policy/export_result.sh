#!/bin/bash
# Export script for enforce_strong_password_policy task

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the final settings from OpenProject via Rails runner
# We capture the output into a variable, then extract the JSON part
echo "Querying OpenProject settings..."

RUBY_SCRIPT='
  require "json"
  begin
    result = {
      "min_length" => Setting.password_min_length.to_i,
      "active_rules" => Setting.password_active_rules,
      "timestamp" => Time.now.to_i
    }
    puts "__JSON_START__" + result.to_json + "__JSON_END__"
  rescue => e
    puts "__JSON_START__{ \"error\": \"#{e.message}\" }__JSON_END__"
  end
'

# Run the query
RAILS_OUTPUT=$(op_rails "$RUBY_SCRIPT")

# Extract JSON between markers
JSON_PAYLOAD=$(echo "$RAILS_OUTPUT" | grep -o "__JSON_START__.*__JSON_END__" | sed 's/__JSON_START__//;s/__JSON_END__//')

# If extraction failed, default to empty error json
if [ -z "$JSON_PAYLOAD" ]; then
    JSON_PAYLOAD='{"error": "Failed to extract settings from Rails output"}'
fi

# Save to result file
echo "$JSON_PAYLOAD" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="