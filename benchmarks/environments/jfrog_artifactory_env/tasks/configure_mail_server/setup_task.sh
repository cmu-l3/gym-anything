#!/bin/bash
set -e
echo "=== Setting up configure_mail_server task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory
wait_for_artifactory 120
echo "Artifactory is accessible."

# ==============================================================================
# RESET MAIL SERVER CONFIGURATION
# We use the YAML configuration PATCH endpoint to clear any existing settings.
# This ensures the agent starts from a clean state.
# ==============================================================================
echo "Resetting mail server configuration..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PATCH \
    -H "Content-Type: application/yaml" \
    -d '
mailServer:
  enabled: false
  host: null
  port: null
  from: null
  subjectPrefix: null
  username: null
  password: null
  ssl: false
  tls: false
' \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /dev/null

# Capture initial config hash for anti-gaming (to prove it changed)
INITIAL_CONFIG=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/system/configuration")
echo "$INITIAL_CONFIG" | md5sum | awk '{print $1}' > /tmp/initial_config_hash.txt
echo "Initial config hash recorded."

# ==============================================================================
# PREPARE BROWSER
# ==============================================================================
# Ensure Firefox is running and logged in
ensure_firefox_running "${ARTIFACTORY_URL}/ui/login"
sleep 5

# Perform login if on login page
# We use a simple python script to check window title or just blindly type if needed
# But ensure_firefox_running often leaves it open.
# We'll try to log in via xdotool if we see the login page, or just assume the agent can do it.
# To be helpful, we'll try to get past the login screen if it's there.

navigate_to "${ARTIFACTORY_URL}/ui/login"
sleep 5

# Type credentials
DISPLAY=:1 xdotool type --clearmodifiers "${ADMIN_USER}" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "${ADMIN_PASS}" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Navigate to home to ensure clean start
navigate_to "${ARTIFACTORY_URL}/ui/"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="