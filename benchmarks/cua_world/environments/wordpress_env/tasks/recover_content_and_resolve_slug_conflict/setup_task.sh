#!/bin/bash
echo "=== Setting up recover_content task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

cd /var/www/html/wordpress

# Create 2023 report
POST_2023_ID=$(wp post create --post_type=post --post_status=publish --post_title="Global Climate Report 2023" --post_content="This is the 2023 report. We have been collecting data on climate change for many years." --porcelain --allow-root)

# Create 2024 original report with realistic text
cat > /tmp/climate2024.txt << 'EOF'
According to the National Oceanic and Atmospheric Administration (NOAA) Annual Climate Report, 2024 saw significant shifts in global temperature anomalies.
This report details the findings from various observation stations across the globe, indicating a clear need for sustainable infrastructure.
EOF

POST_2024_ORIG_ID=$(wp post create --post_type=post --post_status=publish --post_title="Global Climate Report 2024" --post_content="$(cat /tmp/climate2024.txt)" --porcelain --allow-root)

# Trash the 2024 original report
wp post delete $POST_2024_ORIG_ID --allow-root

# Create the intern draft (it will steal the permalink 'global-climate-report-2024' because it has the same title)
POST_DRAFT_ID=$(wp post create --post_type=post --post_status=draft --post_title="Global Climate Report 2024" --post_content="Need to write the 2024 report here..." --porcelain --allow-root)

# Securely save the IDs to ground truth (hidden from the agent)
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth
cat > /var/lib/app/ground_truth/task_ids.json << EOF
{
  "post_2023_id": $POST_2023_ID,
  "post_2024_orig_id": $POST_2024_ORIG_ID,
  "post_draft_id": $POST_DRAFT_ID
}
EOF
chmod 600 /var/lib/app/ground_truth/task_ids.json

# Ensure Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="