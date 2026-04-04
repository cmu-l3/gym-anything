#!/bin/bash
# Setup for agile_user_story_map

echo "=== Setting up User Story Map Task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up previous run artifacts
rm -f /home/ga/Desktop/foodrescue_storymap.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/foodrescue_storymap.png 2>/dev/null || true

# 1. Create the Backlog Text File
cat > /home/ga/Desktop/foodrescue_backlog.txt << 'EOF'
FOODRESCUE APP - PRODUCT BACKLOG
================================

ACTIVITY 1: Registration
- Story: Sign up as Restaurant Donor [MVP]
- Story: Sign up as Shelter/Charity [MVP]
- Story: Single Sign-On (Google/Apple) [V2]
- Story: Verify Non-Profit Status Document [V2]

ACTIVITY 2: Donation Posting
- Story: Create New Donation Listing [MVP]
- Story: Upload Photo of Food [MVP]
- Story: Set Expiration Time [MVP]
- Story: Bulk Upload via CSV [V2]
- Story: Recurring Daily Donation Template [V2]

ACTIVITY 3: Inventory Browse
- Story: View Available Donations List [MVP]
- Story: View Map of Nearby Donations [MVP]
- Story: Filter by Food Type (Veg/Meat) [MVP]
- Story: Real-time Push Notifications [V2]

ACTIVITY 4: Claim Process
- Story: Claim Donation Item [MVP]
- Story: Generate Pickup Code [MVP]
- Story: In-app Chat with Donor [V2]
- Story: Schedule Pickup Window [V2]

ACTIVITY 5: Impact Tracking
- Story: View History of Donations [MVP]
- Story: View Total Weight Saved Dashboard [V2]
- Story: Generate Tax Receipt PDF [V2]
EOF

chown ga:ga /home/ga/Desktop/foodrescue_backlog.txt
chmod 644 /home/ga/Desktop/foodrescue_backlog.txt

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 2. Launch draw.io (Blank Canvas)
echo "Launching draw.io..."
# We launch without a file argument so it shows the startup dialog
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_storymap.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Escape -> New Diagram)
# For this task, starting with a blank diagram is essential.
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/storymap_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="