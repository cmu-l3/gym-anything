#!/bin/bash
set -e

echo "=== Setting up create_kanban_board task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# 1. Enable board_view module for ecommerce-platform project
# This ensures the 'Boards' menu item is actually visible
echo "Enabling board_view module..."
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '
project = Project.find_by(identifier: \"ecommerce-platform\")
if project
  # Enable the module if not already enabled
  unless project.enabled_modules.exists?(name: \"board_view\")
    project.enabled_modules.create(name: \"board_view\")
    puts \"board_view module enabled\"
  end
else
  puts \"ERROR: project not found\"
end
'" 2>/dev/null || echo "WARN: Could not enable board_view module"

# 2. Record initial board count for anti-gaming verification
# We count how many boards currently exist in this project
INITIAL_COUNT=$(docker exec openproject bash -lc "cd /app && bin/rails runner -e production '
project = Project.find_by(identifier: \"ecommerce-platform\")
if project
  # Boards are stored in grids table
  count = Grids::Grid.where(project: project).select { |g| g.type.to_s.include?(\"Board\") }.count
  puts count
else
  puts \"0\"
end
'" 2>/dev/null | tail -1 || echo "0")

echo "${INITIAL_COUNT}" > /tmp/initial_board_count.txt
echo "Initial board count: ${INITIAL_COUNT}"

# 3. Launch Firefox to the project overview page
# We don't go directly to boards to force the agent to find the navigation item
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform" 8

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="