#!/bin/bash
set -e

echo "=== Exporting create_kanban_board result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Board Data via Rails Runner
# We look for the specific board by name and extract its properties
RUBY_CHECK=$(cat << 'RUBY_EOF'
require 'json'

begin
  project = Project.find_by(identifier: 'ecommerce-platform')
  
  if project.nil?
    puts JSON.generate({ error: 'Project not found' })
    exit
  end

  # Find all boards in the project
  all_boards = Grids::Grid.where(project: project).select { |g| g.type.to_s.include?('Board') }
  
  # Find the specific target board
  target_name = 'design workflow board'
  board = all_boards.find { |b| b.name.to_s.downcase.strip == target_name }
  
  result = {
    project_found: true,
    total_board_count: all_boards.count,
    board_found: !board.nil?,
    board_data: nil
  }

  if board
    # Extract options to determine type (action vs basic)
    # Status boards usually have options: { "type" => "action", "attribute" => "status" }
    opts = board.options || {}
    
    # Count columns (widgets)
    # We try to get the query info associated with widgets if possible
    columns = []
    board.widgets.each do |w|
      # Try to get the name of the column if available (often stored in options or related query)
      # For status boards, the widget often represents a query filter for that status
      col_info = { id: w.id }
      if w.options && w.options['name']
         col_info[:name] = w.options['name']
      elsif w.options && w.options['queryId']
         # Try to find the query to see the status name
         begin
           q = Query.find_by(id: w.options['queryId'])
           col_info[:query_name] = q.name if q
           # For status boards, the filter usually indicates the status
         rescue
         end
      end
      columns << col_info
    end

    result[:board_data] = {
      name: board.name,
      type_option: opts['type'],          # e.g. "action"
      attribute_option: opts['attribute'], # e.g. "status"
      column_count: board.widgets.count,
      columns: columns
    }
  end

  puts JSON.generate(result)

rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
RUBY_EOF
)

# Run the ruby script inside the container
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '$RUBY_CHECK'" > /tmp/board_check_raw.json 2>/dev/null || true

# Clean up output (Rails runner might output deprecation warnings or logs before the JSON)
# We look for the last line that looks like JSON
cat /tmp/board_check_raw.json | grep -v "^W," | grep "^{" | tail -1 > /tmp/board_check_clean.json || echo "{}" > /tmp/board_check_clean.json

# 3. Read other state files
INITIAL_COUNT=$(cat /tmp/initial_board_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Construct Final Result JSON
# Use python to merge everything cleanly
python3 -c "
import json
import os
import sys

try:
    with open('/tmp/board_check_clean.json', 'r') as f:
        rails_data = json.load(f)
except Exception as e:
    rails_data = {'error': str(e)}

result = {
    'rails_data': rails_data,
    'initial_board_count': int('$INITIAL_COUNT'),
    'task_start': int('$TASK_START'),
    'task_end': int('$TASK_END'),
    'screenshot_exists': os.path.exists('/tmp/task_final.png')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions so host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="