#!/bin/bash
echo "=== Exporting task results ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Database State (Did they create the query?)
# We use a Ruby script inside the container to inspect the Query object
cat > /tmp/verify_query.rb <<EOF
require 'json'

begin
  # Find query by name (case insensitive)
  query = Query.where("lower(name) = ?", "monthly billing view").first
  
  result = {
    found: !query.nil?,
    timestamp: Time.now.to_i
  }

  if query
    # Check type (should be TimeEntryQuery)
    result[:type] = query.type
    
    # Check visibility (0=Private, 2=Public/Any User)
    result[:visibility] = query.visibility
    
    # Check grouping
    result[:group_by] = query.group_by
    
    # Check columns
    # column_names returns an array of symbols/strings representing selected columns
    result[:columns] = query.column_names.map(&:to_s)
    
    # Check creation time for anti-gaming
    result[:created_on] = query.created_on.to_i
  end

  File.write('/tmp/query_verification.json', result.to_json)
rescue => e
  File.write('/tmp/query_verification.json', { error: e.message }.to_json)
end
EOF

docker cp /tmp/verify_query.rb redmine:/tmp/verify_query.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/verify_query.rb

# Copy the internal verification result to the host
docker cp redmine:/tmp/query_verification.json /tmp/db_result.json 2>/dev/null || echo "{}" > /tmp/db_result.json

# 3. Combine into final result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_RESULT=$(cat /tmp/db_result.json)

# Create final JSON
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "db_check": $DB_RESULT,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json