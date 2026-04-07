#!/bin/bash
set -e
echo "=== Setting up configure_regional_system_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Reset settings to defaults to ensure a clean start
# Default: UTC, Sunday (7), ISO date, etc.
echo "Resetting system settings to defaults..."
cat > /tmp/reset_settings.rb << 'RUBY'
begin
  Setting.time_zone = 'UTC'
  Setting.start_of_week = '7' # Sunday
  Setting.date_format = '%Y-%m-%d'
  Setting.time_format = '%I:%M %p'
  puts "Settings reset successfully"
rescue => e
  puts "Error resetting settings: #{e.message}"
end
RUBY

op_rails "$(< /tmp/reset_settings.rb)"

# Launch Firefox and navigate to login or home
# We want to place the agent at a starting point where they have to find Administration
launch_firefox_to "http://localhost:8080/my/page" 5

# Ensure window is maximized
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="