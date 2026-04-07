#!/bin/bash
set -e

echo "=== Exporting task results: move_work_package_cross_project ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# Query Final State via Rails Runner
# -----------------------------------------------------------------------
echo "Querying final work package state..."

cat > /tmp/check_final.rb << 'RUBY'
require "json"
begin
  # Find WPs with the exact subject
  wps = WorkPackage.where(subject: "Set up application monitoring and alerting")
  
  results = wps.map do |wp|
    {
      id: wp.id,
      subject: wp.subject,
      project_identifier: wp.project.identifier,
      project_name: wp.project.name,
      updated_at: wp.updated_at.to_i
    }
  end
  
  out = {
    count: wps.count,
    work_packages: results,
    timestamp: Time.now.to_i
  }
  
  File.write("/tmp/final_wp_state.json", JSON.generate(out))
rescue => e
  File.write("/tmp/final_wp_state.json", JSON.generate({error: e.message}))
end
RUBY

# Run Ruby script in container
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '/tmp/check_final.rb'"

# Copy result out of container
docker cp openproject:/tmp/final_wp_state.json /tmp/final_wp_state.json 2>/dev/null || echo "{}" > /tmp/final_wp_state.json

# -----------------------------------------------------------------------
# Construct Final Result JSON
# -----------------------------------------------------------------------

# Read initial state if available
if [ -f /tmp/initial_wp_state.json ]; then
    INITIAL_JSON=$(cat /tmp/initial_wp_state.json)
else
    INITIAL_JSON="{}"
fi

FINAL_JSON=$(cat /tmp/final_wp_state.json)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create combined result file
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": $INITIAL_JSON,
    "final_state": $FINAL_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="