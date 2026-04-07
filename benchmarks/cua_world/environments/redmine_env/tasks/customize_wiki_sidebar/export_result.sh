#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if Firefox is running (context)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Extract Database State using Rails Runner
# We run a ruby script inside the container to inspect the Wiki models directly.
# This is more reliable than scraping or API for verifying internal links/content.

RUBY_SCRIPT=$(cat <<EOF
require 'json'

begin
  project = Project.find_by(identifier: 'engineering-handbook')
  
  result = {
    timestamp: Time.now.to_i,
    project_found: !!project,
    wiki_found: !!(project && project.wiki),
    sidebar_page: nil,
    target_pages: {}
  }

  if project && project.wiki
    # Check Sidebar
    sidebar = project.wiki.find_page('Sidebar')
    if sidebar
      result[:sidebar_page] = {
        exists: true,
        content: sidebar.content.text,
        version: sidebar.content.version,
        updated_on: sidebar.content.updated_on.to_i
      }
    else
      result[:sidebar_page] = { exists: false }
    end

    # Check Target Pages
    # Redmine normalizes titles (spaces -> underscores)
    targets = ['Coding_Standards', 'Deployment_Procedures', 'Onboarding_Checklist']
    targets.each do |title|
      page = project.wiki.find_page(title)
      result[:target_pages][title] = {
        exists: !!page,
        has_content: (page && page.content && page.content.text.length > 0)
      }
    end
  end

  puts result.to_json
rescue => e
  puts({ error: e.message }.to_json)
end
EOF
)

# Execute the script inside the container and capture output
# We use a temp file to avoid issues with quoting/escaping in variables
echo "$RUBY_SCRIPT" > /tmp/verify_script.rb
docker cp /tmp/verify_script.rb redmine:/tmp/verify_script.rb

echo "Running verification script inside container..."
DB_RESULT_JSON=$(docker exec redmine bundle exec rails runner /tmp/verify_script.rb 2>/dev/null || echo '{"error": "Execution failed"}')

# 4. Construct Final JSON Output
# We combine the DB result with environment metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_state": $DB_RESULT_JSON
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/verify_script.rb

echo "Exported result to /tmp/task_result.json"
echo "=== Export complete ==="