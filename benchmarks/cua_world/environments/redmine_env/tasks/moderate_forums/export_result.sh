#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting moderate_forums results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract database state using Rails runner
# We need to verify:
# - New board "Technical Q&A" exists
# - Message 1 is in "Technical Q&A"
# - Message 2 is locked

CHECK_SCRIPT="/tmp/check_moderate_forums.rb"
cat > "$CHECK_SCRIPT" <<EOF
require 'json'

result = {
  technical_board_exists: false,
  technical_board_desc_correct: false,
  message_moved: false,
  message_locked: false,
  error: nil
}

begin
  project = Project.find_by(identifier: 'community-support')
  
  # Check for new board
  tech_board = Board.where(project_id: project.id, name: 'Technical Q&A').first
  if tech_board
    result[:technical_board_exists] = true
    result[:technical_board_desc_correct] = (tech_board.description.strip == 'Strictly for technical support and bug reports')
  end

  # Check moved message
  msg_moved = Message.find_by(subject: 'Connection Refused on Port 8080')
  if msg_moved && tech_board
    result[:message_moved] = (msg_moved.board_id == tech_board.id)
  end

  # Check locked message
  msg_locked = Message.find_by(subject: 'Weekly Sync Notes - Jan 2024')
  if msg_locked
    result[:message_locked] = msg_locked.locked?
  end

rescue => e
  result[:error] = e.message
end

puts result.to_json
EOF

docker cp "$CHECK_SCRIPT" redmine:/tmp/check_moderate_forums.rb
docker exec -e SECRET_KEY_BASE=xyz redmine bundle exec rails runner /tmp/check_moderate_forums.rb > /tmp/db_result.json

# 3. Create final result JSON
# Merge the DB result with environment checks
DB_JSON=$(cat /tmp/db_result.json || echo "{}")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final JSON structure safely
jq -n \
  --argjson db "$DB_JSON" \
  --arg start "$TASK_START" \
  --arg end "$TASK_END" \
  '{
    db_state: $db,
    task_start: $start,
    task_end: $end,
    screenshot_path: "/tmp/task_final.png"
  }' > /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json