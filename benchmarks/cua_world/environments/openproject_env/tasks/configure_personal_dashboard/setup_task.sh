#!/bin/bash
echo "=== Setting up Configure Personal Dashboard Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is up and reachable
wait_for_openproject

# Reset Bob Smith's dashboard to default state if necessary
# We want to ensure it's not already in the target state to prevent false positives.
# This ruby script deletes any custom MyPage for Bob, forcing OpenProject to use the default (cluttered) one next time he logs in.
echo "Resetting dashboard state for bob.smith..."
op_rails "
  u = User.find_by(login: 'bob.smith')
  if u
    g = Grid.where(user_id: u.id, type: 'Grids::MyPage').destroy_all
    puts 'Dashboard reset.'
  end
"

# Launch Firefox to the login page
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/login" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="