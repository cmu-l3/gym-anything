#!/bin/bash
# Setup script for customize_project_overview task
# Ensures OpenProject is running, resets the project dashboard to default, and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "=== Setting up customize_project_overview task ==="

# 1. Wait for OpenProject
wait_for_openproject

# 2. Reset the dashboard for 'Mobile Banking App' to ensure clean state
# We delete any existing custom Grids::Overview for this project so the agent starts from default.
echo "Resetting project overview grid..."
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p
    grid = Grids::Overview.find_by(project_id: p.id)
    if grid
      grid.destroy
      puts 'Custom grid destroyed, reset to default.'
    else
      puts 'No custom grid found, already at default.'
    end
  end
"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox to the target project overview
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app" 8

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="