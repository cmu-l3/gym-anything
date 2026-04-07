#!/bin/bash
set -e
echo "=== Setting up create_meeting_with_minutes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Enable the meetings module for E-Commerce Platform project
# This is critical because the module might not be enabled by default
echo "Enabling meetings module..."
docker exec openproject bash -lc "cd /app && bin/rails runner -e production \"
p = Project.find_by(identifier: %q(ecommerce-platform))
if p
  EnabledModule.find_or_create_by(project: p, name: %q(meetings))
  puts %q(Meetings module enabled for ) + p.name
else
  puts %q(ERROR: Project not found)
end
\"" || echo "WARN: Could not enable meetings module via Rails runner"

sleep 3

# Record initial meeting count for anti-gaming (to detect if agent actually created one)
INITIAL_COUNT=$(docker exec openproject bash -lc "cd /app && bin/rails runner -e production \"
p = Project.find_by(identifier: %q(ecommerce-platform))
puts Meeting.where(project: p).count
\"" 2>/dev/null | tail -1 || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_meeting_count.txt
echo "Initial meeting count: $INITIAL_COUNT"

# Launch Firefox directly to the meetings page
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/meetings"
sleep 8
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="