#!/bin/bash
echo "=== Setting up calendar task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure target directory exists
su - ga -c "mkdir -p /home/ga/Documents"

# Create the realistic draft schedule ICS file
cat > /home/ga/Documents/draft_schedule.ics << 'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Mozilla.org/NONSGML Mozilla Calendar V1.1//EN
BEGIN:VEVENT
CREATED:20260301T000000Z
LAST-MODIFIED:20260301T000000Z
DTSTAMP:20260301T000000Z
UID:event1@construction.local
SUMMARY:Excavation - Phase 1
DTSTART:20260418T080000
DTEND:20260418T160000
END:VEVENT
BEGIN:VEVENT
CREATED:20260301T000000Z
LAST-MODIFIED:20260301T000000Z
DTSTAMP:20260301T000000Z
UID:event2@construction.local
SUMMARY:Formwork - Phase 2
DTSTART:20260419T080000
DTEND:20260419T160000
END:VEVENT
BEGIN:VEVENT
CREATED:20260301T000000Z
LAST-MODIFIED:20260301T000000Z
DTSTAMP:20260301T000000Z
UID:event3@construction.local
SUMMARY:Concrete Pour - Phase 3
DTSTART:20260420T080000
DTEND:20260420T120000
DESCRIPTION:Initial pour schedule.
END:VEVENT
BEGIN:VEVENT
CREATED:20260301T000000Z
LAST-MODIFIED:20260301T000000Z
DTSTAMP:20260301T000000Z
UID:event4@construction.local
SUMMARY:Curing & Inspection - Phase 4
DTSTART:20260421T080000
DTEND:20260421T120000
END:VEVENT
END:VCALENDAR
EOF
chown ga:ga /home/ga/Documents/draft_schedule.ics

# Clean any existing internal calendar DBs to ensure a strict anti-gaming environment
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -name "*.default*" -o -name "default-release" | head -n 1 2>/dev/null)
if [ -n "$PROFILE_DIR" ] && [ -d "$PROFILE_DIR/calendar-data" ]; then
    rm -f "$PROFILE_DIR/calendar-data/local.sqlite" 2>/dev/null || true
fi

# Ensure Thunderbird is running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird &"
    sleep 8
fi

# Wait for the Thunderbird window to become available
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "thunderbird"; then
        break
    fi
    sleep 1
done

# Focus and maximize the application for agent visibility
DISPLAY=:1 wmctrl -r "Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Thunderbird" 2>/dev/null || true

# Give the UI a moment to settle
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="