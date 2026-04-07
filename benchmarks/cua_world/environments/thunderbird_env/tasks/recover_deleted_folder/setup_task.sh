#!/bin/bash
echo "=== Setting up recover_deleted_folder task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is NOT running while we modify the file system
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing Thunderbird..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 1
fi

# Set up the Thunderbird profile directory paths
PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
TRASH_SBD="${LOCAL_MAIL_DIR}/Trash.sbd"

# Clean up any existing Q4_Audit files to ensure a clean state
rm -f "${LOCAL_MAIL_DIR}/Q4_Audit" "${LOCAL_MAIL_DIR}/Q4_Audit.msf"
rm -f "${TRASH_SBD}/Q4_Audit" "${TRASH_SBD}/Q4_Audit.msf"

# Ensure Trash directory structure exists
mkdir -p "$TRASH_SBD"
touch "${LOCAL_MAIL_DIR}/Trash"

# Create the accidentally deleted Q4_Audit folder INSIDE the Trash
Q4_MBOX="${TRASH_SBD}/Q4_Audit"
> "$Q4_MBOX"

echo "Populating Q4_Audit folder with read emails..."

# Add 12 standard "read" emails (X-Mozilla-Status: 0001 means READ)
for i in {1..12}; do
cat >> "$Q4_MBOX" <<EOF
From - Mon Jan 01 10:00:0$i 2024
X-Mozilla-Status: 0001
X-Mozilla-Status2: 00000000
From: audit.team@internal-corp.com
To: ga@example.com
Subject: Q4 Audit Document $i
Date: Mon, 01 Jan 2024 10:00:0$i +0000

Please review the attached document $i for the Q4 audit. Everything appears nominal but requires your final sign-off.
EOF
echo "" >> "$Q4_MBOX"
done

# Add 1 URGENT email (Also read initially, not starred)
cat >> "$Q4_MBOX" <<EOF
From - Mon Jan 01 12:00:00 2024
X-Mozilla-Status: 0001
X-Mozilla-Status2: 00000000
From: auditor@external-compliance.com
To: ga@example.com
Subject: URGENT: Missing Signatures
Date: Mon, 01 Jan 2024 12:00:00 +0000

WARNING: We are missing critical signatures on the Q4 compliance forms. 
Please provide the missing signatures immediately. This is blocking the Q4 audit completion and will result in a penalty if not resolved by end of day.
EOF
echo "" >> "$Q4_MBOX"

# Fix ownership
chown -R ga:ga "$PROFILE_DIR"

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release > /tmp/thunderbird.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Click center of desktop to ensure window manager focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="