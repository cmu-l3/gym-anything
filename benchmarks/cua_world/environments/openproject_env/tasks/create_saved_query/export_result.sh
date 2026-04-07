#!/bin/bash
set -e
echo "=== Exporting create_saved_query task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# VERIFICATION LOGIC (Rails Runner)
# ------------------------------------------------------------------
# We run a ruby script inside the container to inspect the database.
# This script outputs a JSON object with the verification results.

RUBY_SCRIPT=$(cat << 'EOF'
require 'json'

begin
  # 1. Find the query
  q = Query.where(name: 'Bobs Backlog Items').last
  
  result = {
    found: false,
    project_match: false,
    has_status_filter: false,
    has_assignee_filter: false,
    filter_details: []
  }

  if q
    result[:found] = true
    
    # 2. Check Project
    if q.project && q.project.identifier == 'ecommerce-platform'
      result[:project_match] = true
    end

    # 3. Check Filters
    # Filters are stored in the 'filters' attribute (list of Filter objects)
    # We need to look for specific operators and values.
    
    # Pre-fetch IDs for "New" status and "Bob Smith" user
    status_new = Status.find_by(name: 'New')
    user_bob = User.find_by(login: 'bob.smith')
    
    q.filters.each do |filter|
      fname = filter.name.to_s
      fvalues = filter.values.map(&:to_s)
      
      filter_info = { name: fname, values: fvalues }
      result[:filter_details] << filter_info

      # Check Status Filter
      if (fname == 'status_id' || fname == 'status')
        # OpenProject stores values as strings of IDs
        if status_new && fvalues.include?(status_new.id.to_s)
           result[:has_status_filter] = true
        end
      end

      # Check Assignee Filter
      if (fname == 'assigned_to_id' || fname == 'assigned_to')
        if user_bob && fvalues.include?(user_bob.id.to_s)
           result[:has_assignee_filter] = true
        end
      end
    end
  end

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
EOF
)

# Execute the Ruby script inside the container
echo "Running verification script in container..."
# We use docker exec directly here to capture stdout cleanly
JSON_OUTPUT=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_SCRIPT\"" 2>/dev/null || echo '{"error": "Rails runner failed"}')

# If the output contains Rails noise (logs), try to extract just the JSON
# (Simple heuristic: take the last line that looks like JSON)
CLEAN_JSON=$(echo "$JSON_OUTPUT" | grep -o '{.*}' | tail -n 1)
if [ -z "$CLEAN_JSON" ]; then
    CLEAN_JSON="{}"
fi

# Create the final result file
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "rails_verification": $CLEAN_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="