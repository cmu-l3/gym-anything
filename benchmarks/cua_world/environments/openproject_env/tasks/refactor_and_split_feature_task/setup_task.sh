#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Refactor and Split Task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Identify the target Work Package ID
# We look for "Implement product search with Elasticsearch" in "ecommerce-platform"
TARGET_WP_ID=$(get_wp_id "ecommerce-platform" "product search with Elasticsearch")

if [ -z "$TARGET_WP_ID" ]; then
    echo "ERROR: Could not find target work package."
    exit 1
fi

echo "Target Work Package ID: $TARGET_WP_ID"
echo "$TARGET_WP_ID" > /tmp/target_wp_id.txt

# 4. Record Initial State (to ensure we track changes)
# We use a simple Rails runner to get the current subject/estimate
op_rails "
  wp = WorkPackage.find($TARGET_WP_ID)
  File.write('/tmp/initial_wp_state.json', {
    id: wp.id,
    subject: wp.subject,
    estimated_hours: wp.estimated_hours,
    lock_version: wp.lock_version
  }.to_json)
"

# 5. Launch Firefox to the Work Packages list of the project
# We start at the list so the agent has to find the WP, or we could open the WP directly.
# The task description says "Open the existing feature...", implying navigation.
# Landing on the list is a good starting point.
PROJECT_URL="http://localhost:8080/projects/ecommerce-platform/work_packages"
launch_firefox_to "$PROJECT_URL" 10

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="