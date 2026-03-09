#!/bin/bash
set -e

echo "=== Setting up task: Add New Phone Codes ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data File (CSV)
# Real recent area code overlays:
# 324: Florida (Jacksonville overlay, EST)
# 729: Tennessee (Chattanooga overlay, EST)
# 839: South Carolina (Columbia overlay, EST)
mkdir -p /home/ga/Documents/VicidialData
cat > /home/ga/Documents/VicidialData/new_areacodes.csv << 'EOF'
CountryCode,AreaCode,GMT_Offset,DST,DST_Range,State,Description
1,324,-5.00,Y,SSM-FSN,FL,Jacksonville Overlay
1,729,-5.00,Y,SSM-FSN,TN,Chattanooga Overlay
1,839,-5.00,Y,SSM-FSN,SC,Columbia Overlay
EOF
chown -R ga:ga /home/ga/Documents/VicidialData
chmod 644 /home/ga/Documents/VicidialData/new_areacodes.csv

# 3. Clean State (Idempotency)
# Ensure Vicidial container is running first
vicidial_ensure_running

# Remove these codes if they already exist so the agent has to add them
echo "Cleaning up any pre-existing phone codes..."
# Wait for MySQL to be ready just in case
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_phone_codes WHERE areacode IN ('324', '729', '839');"

# 4. Ensure Firefox is open and logged in
# The environment hook launches Firefox, but we make sure it's focused and at the right URL
START_URL="${VICIDIAL_ADMIN_URL}"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$START_URL' &"
    wait_for_window "Firefox" 60
fi

# Navigate to Admin home
navigate_to_url "$START_URL"

# Focus and maximize
focus_firefox
maximize_active_window

# 5. Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_phone_codes WHERE areacode IN ('324', '729', '839');")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="