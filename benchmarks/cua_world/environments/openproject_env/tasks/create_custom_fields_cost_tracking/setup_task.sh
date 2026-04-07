#!/bin/bash
# Setup for create_custom_fields_cost_tracking task
set -e

echo "=== Setting up create_custom_fields_cost_tracking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Ensure no custom fields with our target names exist (clean state)
echo "Ensuring clean state: removing any pre-existing custom fields with target names..."
op_rails "
  CustomField.where(name: ['Cost Category', 'Estimated Budget (USD)']).destroy_all
  puts 'Cleaned up target custom fields.'
"

# Record initial custom field count for anti-gaming (to prove something was added)
op_rails "puts 'INITIAL_CF_COUNT:' + CustomField.count.to_s" > /tmp/initial_cf_count_raw.txt
cat /tmp/initial_cf_count_raw.txt | grep "INITIAL_CF_COUNT" | cut -d':' -f2 > /tmp/initial_cf_count.txt || echo "0" > /tmp/initial_cf_count.txt
echo "Initial custom field count: $(cat /tmp/initial_cf_count.txt)"

# Launch Firefox to login page
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/login" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="