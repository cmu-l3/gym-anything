#!/bin/bash
# Setup script for escalate_project_health_status task

source /workspace/scripts/task_utils.sh

echo "=== Setting up escalate_project_health_status task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Reset Project Status for 'Mobile Banking App' (ensure it starts clean)
# We use the Rails runner to delete any existing status or set it to On Track
echo "Resetting project status..."
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app');
  if p
    # Destroy existing status if any to force a fresh creation/update interaction
    p.status.destroy if p.status
    puts 'Project status cleared'
  else
    puts 'Project not found'
  end
"

# 3. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox and login
# We launch directly to the login page, then to the project overview
# The agent needs to log in as admin
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/login" 5

# Auto-login helper (optional, but reduces tedium for this specific task focus)
# Note: In a real 'hard' task we might make the agent login, but here the focus is on the status update.
# However, the description implies the agent starts logged in or knows credentials.
# Let's log them in to the project overview to start the task cleanly.
navigate_to "http://localhost:8080/login" 2
su - ga -c "DISPLAY=:1 xdotool type 'admin'"
su - ga -c "DISPLAY=:1 xdotool key Tab"
su - ga -c "DISPLAY=:1 xdotool type 'Admin1234!'"
su - ga -c "DISPLAY=:1 xdotool key Return"
sleep 5

# Navigate to the specific project
navigate_to "http://localhost:8080/projects/mobile-banking-app" 5

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="