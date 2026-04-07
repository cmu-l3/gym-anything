#!/bin/bash
echo "=== Setting up configure_system_settings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create a reference file inside the docker container to track modified files precisely
docker exec suitecrm-app touch /tmp/task_start_ref

# 2. Generate a realistic company logo file for the agent to upload
mkdir -p /home/ga/Documents
# Using ImageMagick to generate a labeled logo image
convert -size 200x50 xc:navy -pointsize 20 -fill white -gravity center -draw "text 0,0 'Meridian'" /home/ga/Documents/meridian_logo.png
chown ga:ga /home/ga/Documents/meridian_logo.png
echo "Generated mock logo at /home/ga/Documents/meridian_logo.png"

# 3. Ensure Firefox is running, logged in, and drop the agent at the Admin panel
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Administration&action=index"
sleep 5

# 4. Take initial state screenshot for evidence
take_screenshot /tmp/configure_system_settings_initial.png

echo "=== Setup complete ==="
echo "Task: Apply branding and UI settings in System Settings"