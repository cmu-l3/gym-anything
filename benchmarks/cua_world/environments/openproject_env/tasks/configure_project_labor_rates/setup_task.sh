#!/bin/bash
# Setup script for Configure Project Labor Rates task
# Ensures OpenProject is running, the project exists, users are members, 
# and cleans up any existing rates to ensure a fresh start.

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Project Labor Rates task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Clean up existing rates (Pre-condition enforcement)
# We use the Rails runner to delete any existing HourlyRate records for Alice and Bob in this project.
echo "Cleaning up existing hourly rates..."
op_rails "
  project = Project.find_by(identifier: 'devops-automation')
  alice = User.find_by(login: 'alice.johnson')
  bob = User.find_by(login: 'bob.smith')
  
  if project
    [alice, bob].each do |user|
      if user
        HourlyRate.where(project: project, user: user).destroy_all
        puts \"Cleared rates for #{user.login}\"
      end
    end
  else
    puts 'Project not found during setup!'
  end
"

# 4. Launch Firefox to the Project Overview page
# We start at the project level, agent must find "Project settings" -> "Members"
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/devops-automation" 5

# 5. Capture initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="