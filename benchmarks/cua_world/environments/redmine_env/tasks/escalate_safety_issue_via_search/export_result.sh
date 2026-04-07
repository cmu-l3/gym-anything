#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Read the IDs established during setup
if [ ! -f /tmp/task_setup_ids.json ]; then
  echo "ERROR: Setup IDs file not found!"
  # Create a dummy failure result
  echo '{"error": "Setup failed"}' > /tmp/task_result.json
  exit 1
fi

TARGET_ID=$(jq -r '.target_id' /tmp/task_setup_ids.json)
MARCUS_ID=$(jq -r '.marcus_id' /tmp/task_setup_ids.json)
IMMEDIATE_PRIORITY_ID=$(jq -r '.immediate_priority_id' /tmp/task_setup_ids.json)
DECOY_IDS=$(jq -r '.decoy_ids | join(",")' /tmp/task_setup_ids.json)

# Create a Ruby script to query the final state of these specific issues
cat > /tmp/query_final_state.rb << RB
begin
  target = Issue.find($TARGET_ID)
  
  decoys = Issue.where(id: [$DECOY_IDS])
  decoy_states = decoys.map do |d|
    {
      id: d.id,
      subject: d.subject,
      updated_on: d.updated_on.to_i
    }
  end

  result = {
    target: {
      id: target.id,
      priority_id: target.priority_id,
      assigned_to_id: target.assigned_to_id,
      updated_on: target.updated_on.to_i,
      subject: target.subject
    },
    decoys: decoy_states,
    expected: {
      marcus_id: $MARCUS_ID,
      immediate_priority_id: $IMMEDIATE_PRIORITY_ID
    },
    timestamp: Time.now.to_i
  }
  
  puts result.to_json
rescue => e
  puts({error: e.message}.to_json)
end
RB

echo "Querying Redmine for final state..."
docker cp /tmp/query_final_state.rb redmine:/tmp/query_final_state.rb
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine bundle exec rails runner /tmp/query_final_state.rb > /tmp/query_output.txt 2>/dev/null

# Extract the JSON line
tail -n 1 /tmp/query_output.txt > /tmp/task_result.json

# Add setup timestamp for comparison
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Use jq to add the start_time to the result json
jq --arg start "$START_TIME" '. + {task_start_time: $start}' /tmp/task_result.json > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

# Make readable
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json