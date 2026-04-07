#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Querying SciNote DB for equipment record..."

# Use Rails Runner to export the specific row's cells cleanly as JSON
cat << 'EOF' > /tmp/export_eq.rb
require 'json'
begin
  row = RepositoryRow.find_by(name: 'Mettler Toledo pH Meter')
  res = {
    found: !!row,
    container_today: Date.today.to_s,
    container_next_30: 30.days.from_now.to_date.to_s
  }
  
  if row
    res[:row_updated_at] = row.updated_at.to_i
    cells = {}
    row.repository_cells.includes(:repository_column).each do |c|
      col_name = c.repository_column.name
      # Extract value, fallback to value_date stringified if it was magically saved as a date
      val = c.value_text
      val = c.value_date.to_s if val.blank? && c.respond_to?(:value_date) && c.value_date
      
      cells[col_name] = {
        value: val,
        updated_at: c.updated_at.to_i
      }
    end
    res[:cells] = cells
  end
  puts res.to_json
rescue => e
  puts ({error: e.message}).to_json
end
EOF

# Extract just the JSON output (ignoring Rails deprecation warnings or logs)
DB_JSON=$(docker exec scinote_web bash -c "bundle exec rails runner /tmp/export_eq.rb" | grep -v "^Error" | tail -n 1)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

if [ -z "$DB_JSON" ]; then
    DB_JSON="{}"
fi

# Wrap into final export JSON safely
cat << EOF > /tmp/task_result.json
{
  "task_start": $TASK_START,
  "app_was_running": $APP_RUNNING,
  "db_state": $DB_JSON
}
EOF

chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="