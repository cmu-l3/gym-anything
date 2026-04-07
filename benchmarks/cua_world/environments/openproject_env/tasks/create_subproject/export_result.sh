#!/bin/bash
# Export script for create_subproject task
# Extracts project data from Rails runner to verify creation details

echo "=== Exporting create_subproject results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenProject for the specific project details
# We use a Ruby script inside the container to get precise data
echo "Querying project data..."
RUBY_QUERY="
require 'json'
p = Project.find_by(identifier: 'cicd-pipeline-hardening')
result = {}

if p
  result[:found] = true
  result[:name] = p.name
  result[:identifier] = p.identifier
  result[:description] = p.description.to_s
  result[:parent_identifier] = p.parent ? p.parent.identifier : nil
  result[:parent_name] = p.parent ? p.parent.name : nil
  result[:created_at_epoch] = p.created_at.to_i
  # Get enabled module names (friendly names or internal names)
  result[:enabled_modules] = p.enabled_modules.map { |m| m.name }
else
  result[:found] = false
end

puts result.to_json
"

# Run the query and capture output
# We use the op_rails helper but need to capture stdout specifically
QUERY_RESULT=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_QUERY\"" 2>/dev/null | grep "^{")

# Fallback if query failed or returned nothing
if [ -z "$QUERY_RESULT" ]; then
    QUERY_RESULT='{"found": false, "error": "Query returned no JSON"}'
fi

# Construct final JSON including task metadata
# We use jq to merge the query result with task timing info
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

jq -n \
    --argjson query "$QUERY_RESULT" \
    --arg start_time "$TASK_START" \
    --arg end_time "$TASK_END" \
    '{
        task_start: $start_time,
        task_end: $end_time,
        project_data: $query
    }' > "$TEMP_JSON"

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="