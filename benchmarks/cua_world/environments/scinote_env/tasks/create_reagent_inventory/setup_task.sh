#!/bin/bash
echo "=== Setting up create_reagent_inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any pre-existing repository with the target name to ensure a fresh environment
echo "Cleaning up any existing 'Lab Reagents Q4-2024' repositories..."
cat > /tmp/cleanup_script.rb << 'RUBYEOF'
Repository.where("name ILIKE ?", "%Lab Reagents Q4-2024%").destroy_all
RUBYEOF

docker cp /tmp/cleanup_script.rb scinote_web:/tmp/cleanup_script.rb
docker exec scinote_web bundle exec rails runner /tmp/cleanup_script.rb

# Ensure Firefox is running and navigated to the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Let UI settle
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="