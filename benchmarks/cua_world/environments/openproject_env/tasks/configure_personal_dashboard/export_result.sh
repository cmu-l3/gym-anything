#!/bin/bash
echo "=== Exporting Configure Personal Dashboard Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ruby script to inspect the dashboard state
# It extracts the widgets, their identifiers, and positions for Bob Smith
RUBY_SCRIPT=$(cat <<EOF
require 'json'
begin
  user = User.find_by(login: 'bob.smith')
  if user.nil?
    puts JSON.generate({ error: 'User bob.smith not found' })
    exit
  end

  # Find the MyPage grid
  # OpenProject 12+ uses Grids::MyPage
  grid = Grid.where(user_id: user.id, type: 'Grids::MyPage').first
  
  if grid.nil?
    # If no grid exists yet (user never visited My Page), strictly speaking they haven't configured it.
    # However, sometimes OP creates it on first visit. If it's missing, it's definitely not configured correctly.
    puts JSON.generate({ 
      user_found: true, 
      grid_exists: false,
      widgets: [] 
    })
    exit
  end

  # Extract widget info
  # widgets is an association on the grid object
  widgets_data = grid.widgets.map do |w|
    {
      identifier: w.identifier,
      start_row: w.start_row,
      start_column: w.start_column,
      end_row: w.end_row,
      end_column: w.end_column
    }
  end

  # Determine if grid was updated after task start
  # We check updated_at of the grid
  updated_at_epoch = grid.updated_at.to_i

  result = {
    user_found: true,
    grid_exists: true,
    grid_updated_at: updated_at_epoch,
    widgets: widgets_data
  }
  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
EOF
)

# Run the Ruby script inside the container
echo "Querying dashboard state..."
docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_SCRIPT\"" > /tmp/dashboard_state_raw.json 2>/dev/null

# Extract the JSON part (Rails runner might output deprecation warnings etc.)
# We look for the JSON structure
cat /tmp/dashboard_state_raw.json | grep -o '{.*}' | tail -n 1 > /tmp/dashboard_state.json

# If extraction failed, just copy raw (verifier will handle parsing errors)
if [ ! -s /tmp/dashboard_state.json ]; then
    cp /tmp/dashboard_state_raw.json /tmp/dashboard_state.json
fi

# Create the final result JSON wrapping the dashboard state
# Use a temp file to ensure atomic write and permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "dashboard_state": $(cat /tmp/dashboard_state.json || echo "{}")
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="