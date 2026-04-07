#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up provision_service_account_api task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Redmine is running and ready
wait_for_http "$REDMINE_BASE_URL/login" 120

# 2. Reset specific state: Disable REST API to ensure agent has to enable it
echo "Disabling REST API..."
# We use docker exec to run rails runner inside the container
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "Setting.rest_api_enabled = 0;" 2>/dev/null || true

# 3. Reset specific state: Ensure ci_runner user does NOT exist
echo "Removing any existing ci_runner user..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "User.find_by_login('ci_runner')&.destroy" 2>/dev/null || true

# 4. Clean up output file
rm -f /home/ga/ci_api_key.txt

# 5. Log in as Admin to start
# This utility function handles: stop firefox, clean profile, start firefox, login via xdotool
ensure_redmine_logged_in "$REDMINE_BASE_URL/admin"

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="