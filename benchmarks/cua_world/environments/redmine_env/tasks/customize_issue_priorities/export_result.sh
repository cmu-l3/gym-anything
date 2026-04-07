#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting customize_issue_priorities results ==="

# 1. Take final screenshot
take_screenshot "/tmp/task_final.png"

# 2. Extract Enumerations Data using Rails Runner inside Docker
# This is the most robust way to verify the state regardless of UI
echo "Extracting IssuePriority data from Redmine..."

# We use a small Ruby script executed via rails runner to dump the priorities to JSON
RUBY_SCRIPT="puts IssuePriority.unscoped.order(:position).map { |p| { name: p.name, active: p.active, is_default: p.is_default, position: p.position } }.to_json"

# Execute in container and capture output
# SECRET_KEY_BASE is required for rails runner in this env
JSON_OUTPUT=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "$RUBY_SCRIPT" 2>/dev/null || echo "[]")

# 3. Create Result JSON
# We combine the DB data with timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "priorities": $JSON_OUTPUT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="