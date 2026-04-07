#!/bin/bash
# Export script for configure_system_holidays
# Queries the OpenProject database for the configured non-working days.

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for 2026 Non-Working Days
# We use a Ruby script executed via Rails runner to get structured JSON data.
# This handles model abstraction better than raw SQL.

cat > /tmp/query_holidays.rb << 'RUBY_EOF'
require 'json'

begin
  # Attempt to find the correct model class for non-working days
  # OpenProject has changed this over versions, usually NonWorkingDay
  model = nil
  possible_names = ['NonWorkingDay', 'Calendar::NonWorkingDay']
  
  possible_names.each do |name|
    begin
      model = Object.const_get(name)
      break
    rescue NameError
      next
    end
  end

  if model
    # Query for 2026
    days = model.where("date >= ? AND date <= ?", '2026-01-01', '2026-12-31').order(:date)
    
    result = days.map do |d| 
      {
        date: d.date.to_s,
        name: d.name
      }
    end
    
    puts JSON.generate({ status: "success", holidays: result })
  else
    # Fallback: Raw SQL if ActiveRecord model not found
    sql = "SELECT date, name FROM non_working_days WHERE date >= '2026-01-01' AND date <= '2026-12-31' ORDER BY date"
    results = ActiveRecord::Base.connection.select_all(sql)
    mapped = results.map { |r| { date: r['date'].to_s, name: r['name'] } }
    puts JSON.generate({ status: "success", holidays: mapped, method: "sql" })
  end
rescue => e
  puts JSON.generate({ status: "error", message: e.message, backtrace: e.backtrace })
end
RUBY_EOF

# Execute the query inside the container
echo "Running database query..."
docker exec openproject bash -c "cd /app && bundle exec rails runner /tmp/query_holidays.rb" > /tmp/holidays_raw.json 2>/dev/null

# Clean up the output (rails runner might output deprecation warnings etc.)
# We look for the last line that looks like JSON
tail -n 1 /tmp/holidays_raw.json > /tmp/task_result.json

# 3. Add metadata to the result
# We merge the DB result with timestamp info using python
python3 -c "
import json
import os
import time

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {'status': 'error', 'message': 'Failed to parse Rails output'}

# Add timestamp info
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
    data['task_start_time'] = start_time
except:
    data['task_start_time'] = 0

data['export_time'] = int(time.time())
data['screenshot_path'] = '/tmp/task_final.png'

with open('/tmp/task_result_final.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Move to standard output location (handling permissions)
mv /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json