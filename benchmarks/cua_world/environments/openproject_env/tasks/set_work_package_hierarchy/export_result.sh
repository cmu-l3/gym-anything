#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Verification Logic (Ruby script via Rails Runner)
#    Queries the database and outputs a JSON object with the current state.
#    We do this here because exec_in_env is not available in verifier.py

VERIFY_RUBY='
  require "json"
  
  begin
    project = Project.find_by(identifier: "ecommerce-platform")
    
    # 1. Find Epics
    epic1 = WorkPackage.where(project: project, subject: "Search & Discovery Epic").last
    epic2 = WorkPackage.where(project: project, subject: "Checkout & Payments Epic").last
    
    # 2. Check Children
    # Helper to find child info
    def get_child_info(project, subject_partial)
      wp = WorkPackage.where(project: project).where("subject LIKE ?", "%#{subject_partial}%").first
      return nil unless wp
      {
        id: wp.id,
        parent_id: wp.parent_id,
        subject: wp.subject
      }
    end

    children_map = {
      "product_search" => "Implement product search with Elasticsearch",
      "recommendation" => "Implement product recommendation engine",
      "product_page"   => "Design new product page layout",
      "checkout_bug"   => "Fix broken checkout on mobile Safari"
    }

    children_data = {}
    children_map.each do |key, subj|
      children_data[key] = get_child_info(project, subj)
    end

    result = {
      timestamp: Time.now.to_i,
      project_found: !project.nil?,
      epics: {
        epic1: epic1 ? { id: epic1.id, subject: epic1.subject, created_at: epic1.created_at.to_i } : nil,
        epic2: epic2 ? { id: epic2.id, subject: epic2.subject, created_at: epic2.created_at.to_i } : nil
      },
      children: children_data
    }

    puts "JSON_RESULT:" + result.to_json
  rescue => e
    puts "JSON_RESULT:" + { error: e.message }.to_json
  end
'

# Run verifier script inside container and capture output
echo "Running verification query..."
RAW_OUTPUT=$(docker exec openproject bash -lc "cd /app && bin/rails runner -e production '$VERIFY_RUBY'" 2>/dev/null)

# Extract JSON from output (look for JSON_RESULT: prefix)
JSON_PAYLOAD=$(echo "$RAW_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')

if [ -z "$JSON_PAYLOAD" ]; then
    echo "WARNING: Failed to capture JSON result from Rails runner"
    JSON_PAYLOAD='{"error": "Failed to extract JSON from Rails output"}'
fi

# 4. Save to result file
cat > /tmp/task_result.json << EOF
{
  "task_start_time": $TASK_START,
  "rails_state": $JSON_PAYLOAD,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="