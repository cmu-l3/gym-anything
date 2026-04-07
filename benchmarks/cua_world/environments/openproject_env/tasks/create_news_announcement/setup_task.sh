#!/bin/bash
set -e

echo "=== Setting up create_news_announcement task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Wait for OpenProject to be reachable
wait_for_openproject

# Clean up any pre-existing news items with the target title to ensure clean state
# This prevents the agent from finding an old one and thinking it's done,
# or the verifier finding an old one.
echo "Cleaning up any pre-existing news..."
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p
    News.where(project: p).where('title LIKE ?', '%Security Compliance%').destroy_all
    News.where(project: p).where('title LIKE ?', '%Q4 Deadline%').destroy_all
    puts 'Cleanup complete'
  end
"

# Ensure the News module is enabled for the project
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p
    EnabledModule.find_or_create_by(project: p, name: 'news')
    puts 'News module enabled'
  end
"

# Launch Firefox to the Mobile Banking App project page
# We send them to the project overview, so they have to find the "News" tab/module.
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="