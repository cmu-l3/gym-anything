#!/bin/bash
echo "=== Exporting record_animal_movement result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the animal's current state
# We check:
# 1. Current location name
# 2. Last updated timestamp
# 3. If a movement event exists today
echo "Querying database for animal state..."

docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rails runner '
  require \"json\"
  Tenant.switch!(\"demo\")
  
  animal = Animal.find_by(name: \"Marguerite\")
  
  if animal
    loc_name = animal.location ? animal.location.name : nil
    updated_at_ts = animal.updated_at.to_i
    
    # Check for specific movement entry/event if possible
    # We look for recent items in the logs or operations
    # Simplest proxy: check if updated_at > task_start
    
    result = {
      found: true,
      current_location: loc_name,
      updated_at_ts: updated_at_ts,
      id: animal.id
    }
  else
    result = { found: false }
  end
  
  File.write(\"/tmp/ruby_result.json\", result.to_json)
'"

# Copy the Ruby result out of the container to a temp file
docker cp ekylibre-web:/tmp/ruby_result.json /tmp/ruby_result.json 2>/dev/null || echo '{"found": false}' > /tmp/ruby_result.json

# Combine into final JSON
# We use Python to merge the ruby result with task timing data to ensure valid JSON
python3 -c "
import json
import os
import time

try:
    with open('/tmp/ruby_result.json', 'r') as f:
        db_result = json.load(f)
except:
    db_result = {'found': False}

final_result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'animal_found': db_result.get('found', False),
    'current_location': db_result.get('current_location'),
    'animal_updated_at': db_result.get('updated_at_ts', 0),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="