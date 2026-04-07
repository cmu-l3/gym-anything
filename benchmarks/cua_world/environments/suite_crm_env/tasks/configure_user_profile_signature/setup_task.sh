#!/bin/bash
echo "=== Setting up configure_user_profile_signature task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the support logo image in the Documents folder
echo "Generating local support logo image..."
mkdir -p /home/ga/Documents
# Use ImageMagick to create a realistic corporate logo locally
convert -size 300x80 xc:#ffffff -font DejaVu-Sans-Bold -pointsize 24 -fill #0055a4 -draw "text 20,45 'GLOBAL SUPPORT'" -stroke #0055a4 -strokewidth 3 -draw "line 20,55 280,55" /home/ga/Documents/support_logo.png 2>/dev/null || true
chown ga:ga /home/ga/Documents/support_logo.png

# 2. Clear any existing signatures with the target name (clean slate)
echo "Cleaning up any existing target signatures..."
suitecrm_db_query "UPDATE users_signatures SET deleted=1 WHERE name='Support Standard'"

# 3. Ensure logged in and navigate to the Home dashboard
echo "Ensuring SuiteCRM is logged in..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 4

# 4. Take initial screenshot
take_screenshot /tmp/configure_profile_initial.png

echo "=== Task setup complete ==="
echo "Logo created at: /home/ga/Documents/support_logo.png"
echo "Ready for agent to configure profile, preferences, and signature."