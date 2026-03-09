#!/bin/bash
set -e
echo "=== Setting up update_org_branding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running
ensure_sdp_running

# 1. Generate the logo file
mkdir -p /home/ga/Documents
echo "Generating corporate logo..."
# Create a 300x100 blue logo with text
convert -size 300x100 xc:white -fill "#0047AB" -draw "rectangle 0,0 300,10" \
    -pointsize 30 -fill black -gravity center -draw "text 0,0 'Initrode'" \
    -fill "#0047AB" -pointsize 14 -gravity south -draw "text 0,10 'Global Systems'" \
    /home/ga/Documents/initrode_logo.png 2>/dev/null || \
    # Fallback if convert fails: create simple text file pretending to be image or empty image
    touch /home/ga/Documents/initrode_logo.png

chown ga:ga /home/ga/Documents/initrode_logo.png

# 2. Reset Organization Details to defaults (to ensure we detect changes)
echo "Resetting Organization Details..."
# We try to update the first record in OrganizationDetails
sdp_db_exec "UPDATE organizationdetails SET organizationname='ManageEngine', address='Default Address', email='admin@old.com', phone='000-000-0000', fax='', websiteurl='http://';" 2>/dev/null || true

# 3. Capture initial state
INITIAL_DETAILS=$(sdp_db_exec "SELECT * FROM organizationdetails LIMIT 1;" 2>/dev/null || echo "DB_ERROR")
echo "$INITIAL_DETAILS" > /tmp/initial_org_details.txt

# 4. Launch Firefox to Login Page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 5. Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="