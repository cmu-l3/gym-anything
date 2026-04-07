#!/bin/bash
echo "=== Setting up schedule_meeting_from_request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Generate Dynamic Date (3 days from now)
# We use a fixed offset to ensure the date is always in the future but valid
TARGET_DATE_OBJ=$(date -d "+3 days")
TARGET_DATE_STR=$(date -d "+3 days" '+%A, %B %d, %Y')
TARGET_YMD=$(date -d "+3 days" '+%Y-%m-%d')

# Define Time and Duration
TARGET_TIME_STR="1:30 PM"
TARGET_TIME_24="13:30:00"
DURATION_MINUTES="90"
# End time calculation for verification (Start + 90 min)
TARGET_END_24=$(date -d "$TARGET_YMD $TARGET_TIME_24 $DURATION_MINUTES minutes" '+%H:%M:%S')

# Save expected values to a hidden file for the export script to use
cat > /tmp/task_expected_values.json << EOF
{
    "subject": "Systems Infrastructure Check",
    "date": "$TARGET_YMD",
    "start_time": "$TARGET_TIME_24",
    "end_time": "$TARGET_END_24",
    "duration": 1.5,
    "location": "Server Room",
    "attendees": ["Luis Fernandez", "David Chen"]
}
EOF

# 2. Create the Request File
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/meeting_request.txt << EOF
From: Henry Kim <henry.kim@northbridge.org>
To: Admin <admin@northbridge.org>
Subject: Urgent: Systems Infrastructure Check

Hi Admin,

Could you please schedule a 'Systems Infrastructure Check' for this coming $TARGET_DATE_STR?

We need to start at $TARGET_TIME_STR and it will likely take 90 minutes.

Please book the 'Server Room' and make sure Luis Fernandez and David Chen are invited.

Thanks,
Henry
EOF

chown ga:ga /home/ga/Documents/meeting_request.txt
chmod 644 /home/ga/Documents/meeting_request.txt

echo "Created meeting request for $TARGET_DATE_STR"

# 3. Ensure Firefox is open to Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="