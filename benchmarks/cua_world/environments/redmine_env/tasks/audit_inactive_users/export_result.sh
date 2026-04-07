#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting audit_inactive_users results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Extract user status data from Redmine DB via Rails runner
# We output a JSON object containing the status and last_login for verification
cat > /tmp/verify_users.rb << 'RUBY'
require 'json'
target_logins = ['bwayne', 'ckent', 'dprince', 'ballen', 'admin']
users = User.where(login: target_logins)

data = users.map do |u|
  {
    login: u.login,
    status: u.status, # 1=Active, 3=Locked
    last_login_on: u.last_login_on ? u.last_login_on.iso8601 : nil,
    updated_on: u.updated_on ? u.updated_on.to_i : 0
  }
end

puts JSON.generate({ users: data })
RUBY

docker cp /tmp/verify_users.rb redmine:/tmp/verify_users.rb

# Capture output to temp file
# Filter stdout to find the JSON line (ignore potential rails warnings)
DB_RESULT_JSON=$(mktemp)
docker exec -e RAILS_ENV=production -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner /tmp/verify_users.rb > "$DB_RESULT_JSON" 2>/dev/null || true

# Extract just the JSON part
CLEAN_JSON=$(mktemp)
grep -o '{.*}' "$DB_RESULT_JSON" | head -1 > "$CLEAN_JSON" || echo '{"users": []}' > "$CLEAN_JSON"

# 4. Combine into final result JSON
FINAL_JSON="/tmp/task_result.json"
jq -s '.[0] + {task_start: '"$TASK_START"', task_end: '"$TASK_END"', screenshot_path: "/tmp/task_final.png"}' \
  "$CLEAN_JSON" > "$FINAL_JSON"

# Cleanup
rm -f /tmp/verify_users.rb "$DB_RESULT_JSON" "$CLEAN_JSON" 2>/dev/null || true

# Set permissions for host access
chmod 666 "$FINAL_JSON" 2>/dev/null || sudo chmod 666 "$FINAL_JSON" 2>/dev/null || true

echo "Export complete. Result:"
cat "$FINAL_JSON"