#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting refactor_document_categories result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Redmine DB state via Rails runner
# We need to export the state of categories and the specific document
CHECK_SCRIPT="/tmp/check_state.rb"
cat > "$CHECK_SCRIPT" << 'RUBY'
require 'json'

results = {
  # Category checks
  'tech_doc_exists' => DocumentCategory.where(name: 'Technical documentation').exists?,
  'user_manuals_exists' => DocumentCategory.where(name: 'User Manuals').exists?,
  'test_plans_exists' => DocumentCategory.where(name: 'Test Plans').exists?,
  'audit_reports_exists' => DocumentCategory.where(name: 'Audit Reports').exists?,
  
  # Document checks
  'doc_exists' => false,
  'doc_category' => nil
}

doc = Document.find_by(title: 'Legacy System Spec')
if doc
  results['doc_exists'] = true
  results['doc_category'] = doc.category.try(:name)
end

puts results.to_json
RUBY

docker cp "$CHECK_SCRIPT" redmine:/tmp/check_state.rb
DB_STATE_JSON=$(docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/check_state.rb | tail -n 1)

# 3. Construct final result JSON
# We include timestamps and screenshot info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# Use jq to merge the DB state with metadata (or just manual string construction if jq is limited, but jq is in install script)
# Safely writing to temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "screenshot_exists": $SCREENSHOT_EXISTS,
  "db_state": $DB_STATE_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="