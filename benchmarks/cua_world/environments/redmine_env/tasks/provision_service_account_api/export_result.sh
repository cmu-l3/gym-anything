#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting provision_service_account_api results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Redmine Database (via Rails Runner)
# We collect all verification data into a single JSON object inside the container
# then write it to a temporary file.

echo "Querying Redmine database..."

# Create a ruby script to dump the state we care about
cat > /tmp/verify_state.rb << 'RBEOF'
require 'json'

begin
  # Check API Setting
  api_enabled = Setting.rest_api_enabled.to_i == 1

  # Check User
  u = User.find_by_login('ci_runner')
  
  user_data = nil
  token_value = nil

  if u
    # Get API Token
    # Action 'api' is used for API keys
    t = Token.where(user_id: u.id, action: 'api').last
    token_value = t ? t.value : nil
    
    user_data = {
      "exists" => true,
      "firstname" => u.firstname,
      "lastname" => u.lastname,
      "mail" => u.mail,
      "must_change_passwd" => u.must_change_passwd,
      "created_on" => u.created_on.to_i
    }
  else
    user_data = { "exists" => false }
  end

  result = {
    "api_enabled" => api_enabled,
    "user" => user_data,
    "db_token" => token_value
  }

  puts result.to_json
rescue => e
  puts({ "error" => e.message }.to_json)
end
RBEOF

# Copy script to container
docker cp /tmp/verify_state.rb redmine:/tmp/verify_state.rb

# Run script and capture output
DB_RESULT_JSON=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/verify_state.rb 2>/dev/null || echo '{"error": "Rails runner failed"}')

# 3. Check output file on filesystem
OUTPUT_FILE="/home/ga/ci_api_key.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '[:space:]') # Trim whitespace
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 4. Check if file was created during task
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 5. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $DB_RESULT_JSON,
    "file_check": {
        "exists": $FILE_EXISTS,
        "content": "$FILE_CONTENT",
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "screenshots": {
        "initial": "/tmp/task_initial.png",
        "final": "/tmp/task_final.png"
    }
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/verify_state.rb

echo "Export complete. Result:"
cat /tmp/task_result.json