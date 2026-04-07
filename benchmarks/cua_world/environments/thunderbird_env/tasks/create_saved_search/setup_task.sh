#!/bin/bash
echo "=== Setting up create_saved_search task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"

# Ensure Thunderbird is NOT running so we don't corrupt the mailbox while appending
if pgrep -f "thunderbird" > /dev/null; then
    echo "Closing Thunderbird..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" || true
    sleep 2
fi

# Remove any pre-existing virtualFolders.dat to ensure a clean state
rm -f "${PROFILE_DIR}/virtualFolders.dat"

# Inject realistic budget-themed emails into the Inbox
echo "Injecting budget-themed emails into Inbox..."
mkdir -p "$LOCAL_MAIL_DIR"

cat >> "$INBOX_MBOX" << 'EMAIL_EOF'
From budget-team@acmecorp.com Mon Oct 14 09:15:00 2024
From: Sarah Mitchell <sarah.mitchell@acmecorp.com>
To: testuser@example.com
Subject: Q4 Budget Forecast — Draft for Review
Date: Mon, 14 Oct 2024 09:15:00 -0400
Message-ID: <budget001@acmecorp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Hi team,
Please find attached the Q4 budget forecast draft. I need everyone's input by Wednesday.
Best,
Sarah Mitchell

From d.chen@acmecorp.com Tue Oct 15 11:30:00 2024
From: David Chen <d.chen@acmecorp.com>
To: testuser@example.com
Subject: Re: Budget allocation for new hires
Date: Tue, 15 Oct 2024 11:30:00 -0400
Message-ID: <budget002@acmecorp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Thanks for flagging this. I spoke with HR and we have room in the Q4 budget for two additional analyst positions.
David

From controller@acmecorp.com Wed Oct 16 08:00:00 2024
From: Office of the Controller <controller@acmecorp.com>
To: all-managers@acmecorp.com
Subject: ACTION REQUIRED: Annual budget submission deadline Friday
Date: Wed, 16 Oct 2024 08:00:00 -0400
Message-ID: <budget003@acmecorp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

All department managers,
This is a reminder that annual budget submissions for FY2025 are due by end of business Friday.

From j.rodriguez@acmecorp.com Thu Oct 17 14:22:00 2024
From: Julia Rodriguez <j.rodriguez@acmecorp.com>
To: testuser@example.com
Subject: FYI: Updated budget spreadsheet attached
Date: Thu, 17 Oct 2024 14:22:00 -0400
Message-ID: <budget004@acmecorp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Hey, I just uploaded the revised budget spreadsheet to the shared drive.

From m.thompson@acmecorp.com Fri Oct 18 10:45:00 2024
From: Mark Thompson <m.thompson@acmecorp.com>
To: testuser@example.com
Subject: Meeting notes — budget committee 10/15
Date: Fri, 18 Oct 2024 10:45:00 -0400
Message-ID: <budget005@acmecorp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

All, here are the notes from Tuesday's budget committee meeting.
EMAIL_EOF

# Remove the MSF index so Thunderbird rebuilds it with the new emails
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf"

# Set proper ownership
chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release >/dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# Give Thunderbird time to rebuild index and render UI
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="