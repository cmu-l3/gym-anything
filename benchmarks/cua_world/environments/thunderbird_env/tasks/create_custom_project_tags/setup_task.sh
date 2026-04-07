#!/bin/bash
set -euo pipefail

echo "=== Setting up Create Custom Project Tags task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can safely modify the mbox
close_thunderbird || true
sleep 2

TB_PROFILE="/home/ga/.thunderbird/default-release"
INBOX_FILE="${TB_PROFILE}/Mail/Local Folders/Inbox"

# Ensure the directory exists
mkdir -p "${TB_PROFILE}/Mail/Local Folders/"

# Inject the 3 target emails into the Inbox
echo "Injecting target emails into Inbox..."
cat << 'EOF' >> "$INBOX_FILE"

From audit.dept@apexindustrial.com Mon Mar 02 09:15:00 2026
Date: Mon, 02 Mar 2026 09:15:00 -0500
From: "Audit Department" <audit.dept@apexindustrial.com>
To: "Sarah Mitchell" <testuser@example.com>
Subject: Internal Audit Schedule - FY26
Message-ID: <audit.1@apexindustrial.com>
X-Mozilla-Status: 0001
X-Mozilla-Keys: 

Please review the attached preliminary schedule for the FY26 internal audit. 
Ensure your department's records are available for review during your assigned window.

From compliance@apexindustrial.com Tue Mar 03 14:30:00 2026
Date: Tue, 03 Mar 2026 14:30:00 -0500
From: "Compliance Team" <compliance@apexindustrial.com>
To: "Sarah Mitchell" <testuser@example.com>
Subject: Compliance Review: Q3 Documentation
Message-ID: <compliance.2@apexindustrial.com>
X-Mozilla-Status: 0001
X-Mozilla-Keys: 

We are missing the Q3 signed documentation for the regional suppliers. 
Please upload these to the portal before the external auditors arrive next week.

From vendor.management@apexindustrial.com Wed Mar 04 11:45:00 2026
Date: Wed, 04 Mar 2026 11:45:00 -0500
From: "Vendor Risk Management" <vendor.management@apexindustrial.com>
To: "Sarah Mitchell" <testuser@example.com>
Subject: Vendor Risk Assessment - Action Required
Message-ID: <vendor.3@apexindustrial.com>
X-Mozilla-Status: 0001
X-Mozilla-Keys: 

A high-risk vendor in your portfolio requires an updated risk assessment. 
This must be completed as part of the Audit 2026 preparation workflow.
EOF

# Remove the index file so Thunderbird rebuilds it and sees the new emails
rm -f "${INBOX_FILE}.msf" 2>/dev/null || true

# Fix permissions
chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
echo "Starting Thunderbird..."
start_thunderbird

# Wait for window to appear
wait_for_thunderbird_window 30

# Maximize and focus the window
maximize_thunderbird
sleep 1
WID=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "thunderbird" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Dismiss any potential dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="