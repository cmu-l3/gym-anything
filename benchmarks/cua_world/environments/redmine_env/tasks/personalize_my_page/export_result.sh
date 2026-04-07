#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting 'Personalize My Page' results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot "/tmp/task_final_state.png"

# 2. Query Redmine for the User's Preference Layout
# We fetch the layout hash as JSON directly from Rails
echo "Extracting layout configuration..."
LAYOUT_JSON=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine bundle exec rails runner -e production "
  u = User.find_by_login('admin')
  if u
    print u.pref[:my_page_layout].to_json
  else
    print '{}'
  end
")

echo "Detected Layout: $LAYOUT_JSON"

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "layout_json": $LAYOUT_JSON,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with loose permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"