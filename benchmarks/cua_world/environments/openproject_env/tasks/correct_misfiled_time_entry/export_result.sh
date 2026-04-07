#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the ID we are tracking
if [ ! -f /tmp/target_time_entry_id.txt ]; then
    echo "Error: Target ID file not found."
    echo '{"error": "setup_failed"}' > /tmp/task_result.json
    exit 0
fi

TE_ID=$(cat /tmp/target_time_entry_id.txt)

# Query the current state of this specific time entry
cat > /tmp/inspect_entry.rb << RUBY_EOF
require 'json'
begin
  te = TimeEntry.find_by(id: $TE_ID)
  if te
    result = {
      found: true,
      id: te.id,
      work_package_subject: te.work_package.subject,
      hours: te.hours,
      comments: te.comments,
      project_identifier: te.project.identifier
    }
  else
    result = { found: false }
  end
  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message })
end
RUBY_EOF

# Run query in container
JSON_OUTPUT=$(op_rails "$(cat /tmp/inspect_entry.rb)")

# Extract the JSON line (ignoring any potential rails startup noise)
CLEAN_JSON=$(echo "$JSON_OUTPUT" | grep "^{.*}" | tail -n 1)

# Save to result file
echo "$CLEAN_JSON" > /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json

echo "=== Export Complete ==="