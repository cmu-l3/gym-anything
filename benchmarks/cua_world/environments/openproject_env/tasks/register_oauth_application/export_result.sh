#!/bin/bash
echo "=== Exporting OAuth Registration Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check the output file (Credentials)
CREDENTIALS_FILE="/home/ga/jenkins_credentials.json"
FILE_EXISTS="false"
FILE_CONTENT="{}"
FILE_VALID_JSON="false"

if [ -f "$CREDENTIALS_FILE" ]; then
    FILE_EXISTS="true"
    # Read content safely
    FILE_CONTENT=$(cat "$CREDENTIALS_FILE")
    # Validate JSON structure
    if echo "$FILE_CONTENT" | jq empty 2>/dev/null; then
        FILE_VALID_JSON="true"
    fi
fi

# 3. Query the Database for the OAuth Application
# We use rails runner to output a JSON object describing the app state
DB_RESULT=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"
  require 'json'
  app = Doorkeeper::Application.where(name: 'Jenkins CI Pipeline').last
  res = if app
    {
      found: true,
      name: app.name,
      uid: app.uid,
      redirect_uri: app.redirect_uri,
      scopes: app.scopes.to_s,
      confidential: app.confidential,
      created_at: app.created_at.to_i
    }
  else
    { found: false }
  end
  puts res.to_json
\"" 2>/dev/null || echo '{"found": false, "error": "Rails runner failed"}')

# 4. Construct the final result JSON
# We embed the raw file content and the DB result into one JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

try:
    db_result = json.loads('''$DB_RESULT''')
except:
    db_result = {'found': False, 'error': 'JSON parse failed'}

try:
    file_content = json.loads('''$FILE_CONTENT''')
except:
    file_content = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_valid_json': $FILE_VALID_JSON,
    'file_content': file_content,
    'db_result': db_result,
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result))
" > "$TEMP_JSON"

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="