#!/bin/bash
echo "=== Exporting restructure_wiki_hierarchy result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM/evidence
take_screenshot /tmp/task_final.png

# Query OpenProject state via Rails runner to verify hierarchy and content
# We output a JSON string directly from Ruby for the verifier to consume
echo "Querying OpenProject database..."
RUBY_SCRIPT="
  require 'json'
  
  begin
    project = Project.find_by(identifier: 'mobile-banking-app')
    wiki = project.wiki
    
    # Find the expected parent page
    parent = WikiPage.find_by(wiki: wiki, title: 'Technical Documentation')
    
    # Find the children
    child1 = WikiPage.find_by(wiki: wiki, title: 'System Architecture')
    child2 = WikiPage.find_by(wiki: wiki, title: 'API Endpoints')
    
    # Check for TOC macro (Textile {{toc}} or Markdown [toc])
    content_text = parent&.content&.text || ''
    has_toc = content_text.include?('{{toc}}') || content_text.include?('[toc]')
    
    result = {
      'parent_exists' => !parent.nil?,
      'parent_id' => parent&.id,
      'parent_created_at' => parent&.created_at&.to_i || 0,
      'has_toc' => has_toc,
      'child1_exists' => !child1.nil?,
      'child1_parent_id' => child1&.parent_id,
      'child2_exists' => !child2.nil?,
      'child2_parent_id' => child2&.parent_id,
      'task_start' => $TASK_START
    }
    
    puts JSON.generate(result)
  rescue => e
    puts JSON.generate({'error' => e.message})
  end
"

# Run the ruby script inside the container and capture output
# We filter for the JSON line in case of Rails logging noise
JSON_OUTPUT=$(op_rails "$RUBY_SCRIPT" | grep "^{" | tail -n 1)

# Write to a temp file then move to final location safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$JSON_OUTPUT" > "$TEMP_JSON"

# Save result to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="