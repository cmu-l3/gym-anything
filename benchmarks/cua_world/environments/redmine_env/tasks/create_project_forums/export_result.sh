#!/bin/bash
set -euo pipefail

echo "=== Exporting create_project_forums result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

REDMINE_SKB="redmine_env_secret_key_base_do_not_use_in_production_xyz123"
PROJECT_IDENTIFIER=$(cat /tmp/task_project_identifier.txt 2>/dev/null || echo "")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

if [ -z "$PROJECT_IDENTIFIER" ]; then
    echo "ERROR: Project identifier not found"
    # Create empty result
    echo '{"error": "Project identifier missing"}' > /tmp/task_result.json
    exit 0
fi

# Query Redmine database via Rails runner to get full structure of boards/messages
# We extract this to a JSON object for the verifier to analyze
echo "Querying Redmine database..."

DB_JSON=$(docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
    bundle exec rails runner "
require 'json'
begin
    p = Project.find_by_identifier('$PROJECT_IDENTIFIER')
    if p.nil?
        puts ({ error: 'Project not found' }).to_json
        exit
    end

    result = {
        project: p.identifier,
        boards: [],
        messages: []
    }

    p.boards.each do |b|
        result[:boards] << {
            id: b.id,
            name: b.name,
            description: b.description.to_s,
            created_on: b.created_on.to_i
        }
        
        # Get messages for this board
        b.messages.each do |m|
            result[:messages] << {
                id: m.id,
                board_id: m.board_id,
                board_name: b.name,
                parent_id: m.parent_id,
                subject: m.subject.to_s,
                content: m.content.to_s,
                created_on: m.created_on.to_i,
                replies_count: m.replies_count
            }
        end
    end

    puts result.to_json
rescue => e
    puts ({ error: e.message }).to_json
end
" -e production 2>/dev/null)

# Validate JSON output
if ! echo "$DB_JSON" | jq . >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON from Rails runner"
    echo "$DB_JSON" > /tmp/db_error.log
    DB_JSON='{"error": "Invalid JSON output from DB query", "raw": ""}'
fi

# Wrap in final result object with metadata
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)",
    "redmine_data": $DB_JSON
}
EOF

# Set permissions so python verifier can read it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="