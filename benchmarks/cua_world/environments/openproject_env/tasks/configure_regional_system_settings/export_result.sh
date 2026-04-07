#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract settings from OpenProject using Rails runner
# We output a clean JSON object for the verifier
echo "Querying OpenProject settings..."
cat > /tmp/check_settings.rb << 'RUBY'
require 'json'

begin
  # Fetch current values using the Setting accessor
  current = {
    time_zone: Setting.time_zone,
    start_of_week: Setting.start_of_week,
    date_format: Setting.date_format,
    time_format: Setting.time_format
  }

  # Fetch raw records to check updated_on timestamps
  # Settings are stored as keys in the 'settings' table
  # We check if they were updated after the task start
  raw_updates = {}
  ['time_zone', 'start_of_week', 'date_format', 'time_format'].each do |name|
    s = Setting.find_by(name: name)
    if s
      raw_updates[name] = s.updated_on.to_i
    else
      raw_updates[name] = 0
    end
  end

  result = {
    status: "success",
    values: current,
    timestamps: raw_updates
  }
rescue => e
  result = { status: "error", message: e.message }
end

puts "JSON_START"
puts result.to_json
puts "JSON_END"
RUBY

# Run the ruby script and capture output
RAILS_OUTPUT=$(op_rails "$(< /tmp/check_settings.rb)")

# Extract JSON part
JSON_PAYLOAD=$(echo "$RAILS_OUTPUT" | sed -n '/JSON_START/,/JSON_END/p' | sed '1d;$d')

# Save to result file
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "screenshot_path": "/tmp/task_final.png",
  "rails_data": $JSON_PAYLOAD
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="