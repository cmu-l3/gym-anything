#!/bin/bash
# Setup script for format_longform_article task
echo "=== Setting up format_longform_article task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Record initial post count
INITIAL_POST_COUNT=$(get_post_count "post" "publish")
echo "$INITIAL_POST_COUNT" > /tmp/initial_post_count
chmod 666 /tmp/initial_post_count

# Create the raw draft file with realistic content
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/article_draft.txt << 'EOF'
The shift toward sustainable power generation has accelerated significantly in the 21st century as nations seek to reduce carbon emissions.

[Insert Table of Contents Here]

Solar Energy Technologies
Solar power captures sunlight and converts it into electricity. Photovoltaic cells have become cheaper and more efficient, allowing for massive utility-scale solar farms as well as decentralized rooftop installations. Advanced perovskite materials are currently being researched to push efficiency limits even further.

Wind Power Developments
Wind turbines harness kinetic energy from the wind. Offshore wind farms represent a major growth sector due to stronger, more consistent winds at sea. Modern turbines have grown dramatically in size, with some rotor diameters exceeding 200 meters.

Energy Storage Solutions
Grid-scale batteries and pumped hydro storage are critical to addressing the intermittency of renewable sources. Lithium-ion technology currently dominates short-term storage, while researchers explore flow batteries and compressed air for longer-duration energy reserves.

The transition to 100% renewable energy systems requires not just technological innovation, but comprehensive policy frameworks and international cooperation.

[Embed Video Here... (Use URL: https://www.youtube.com/watch?v=1kUE0BZtTRc)]
EOF

# Ensure the ga user owns the file
chown ga:ga /home/ga/Documents/article_draft.txt
chmod 644 /home/ga/Documents/article_draft.txt

# Start and focus Firefox
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/post-new.php' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="