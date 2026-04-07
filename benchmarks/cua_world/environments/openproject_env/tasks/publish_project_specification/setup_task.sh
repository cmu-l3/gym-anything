#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: publish_project_specification@1 ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Create the dummy specification file for the agent to upload
echo "Official Mobile App Specification 2026 - Confidential" > /home/ga/mobile_spec_v1.txt
chown ga:ga /home/ga/mobile_spec_v1.txt
chmod 644 /home/ga/mobile_spec_v1.txt

# 4. Clean State: Ensure Documents module is DISABLED for the project
echo "Ensuring clean state (module disabled, category removed)..."
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p
    m = p.enabled_modules.find_by(name: 'documents')
    m.destroy if m
  end
"

# 5. Clean State: Ensure 'Specifications' document category does NOT exist
op_rails "
  DocumentCategory.where(name: 'Specifications').destroy_all
"

# 6. Automate Login and Navigation
echo "Launching Firefox and logging in..."
# Start fresh
pkill -f firefox || true

# Launch to login page
launch_firefox_to "http://localhost:8080/login" 5

# Perform Login via xdotool
xdotool type "admin"
xdotool key Tab
xdotool type "Admin1234!"
xdotool key Return
sleep 5

# Navigate to the target project overview
navigate_to "http://localhost:8080/projects/mobile-banking-app" 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="