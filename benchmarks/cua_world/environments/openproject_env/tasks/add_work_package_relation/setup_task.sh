#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_work_package_relation task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Record Initial State (Relation Count)
# We use the Rails runner to get the precise count of relations in the DB
echo "Recording initial relation count..."
INITIAL_REL_COUNT=$(docker exec openproject bash -c "cd /app && bin/rails runner -e production 'puts Relation.count'" 2>/dev/null | tail -n 1 | tr -d '\r')
echo "${INITIAL_REL_COUNT:-0}" > /tmp/initial_relation_count.txt
echo "Initial relation count: ${INITIAL_REL_COUNT:-0}"

# 4. Launch Firefox to the Work Packages list
# This ensures the agent starts in the right place
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 8

# 5. Maximize window for visibility
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="