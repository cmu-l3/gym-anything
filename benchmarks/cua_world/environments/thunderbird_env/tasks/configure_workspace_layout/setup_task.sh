#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Workspace Layout Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"

# Ensure Thunderbird is closed before touching mbox or prefs
echo "Closing Thunderbird to inject target data..."
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

# Remove index to force rebuild so Thunderbird recognizes the new email size
rm -f "${INBOX_MBOX}.msf" 2>/dev/null || true

# Inject a deliberately massive email to test size sorting
# Using /dev/zero and base64 to create a compressible but large dummy attachment
echo "Injecting massive Q4 Financial Report email..."
cat << 'EOF' >> "$INBOX_MBOX"
From boss@example.com Wed Feb 28 10:00:00 2024
Subject: URGENT: Q4 Financial Report
From: Management <boss@example.com>
To: ga@example.com
Date: Wed, 28 Feb 2024 10:00:00 +0000
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="====BOUNDARY===="

--====BOUNDARY====
Content-Type: text/plain; charset=utf-8

Please find the large Q4 Financial Report attached for your review.

--====BOUNDARY====
Content-Type: application/pdf; name="Q4_Financial_Report_Final.pdf"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="Q4_Financial_Report_Final.pdf"

EOF

# Add ~2.5MB of dummy base64 data to make it definitively the largest email in the corpus
head -c 1800000 /dev/zero | base64 >> "$INBOX_MBOX"

echo "" >> "$INBOX_MBOX"
echo "--====BOUNDARY====--" >> "$INBOX_MBOX"
echo "" >> "$INBOX_MBOX"

# Ensure permissions are correct
chown -R ga:ga "$PROFILE_DIR"

# Launch Thunderbird
echo "Launching Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird &" > /dev/null 2>&1
sleep 8 # Give Thunderbird time to start and rebuild Inbox.msf

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Thunderbird"; then
        echo "Thunderbird window found"
        break
    fi
    sleep 1
done

# Focus and maximize the window to ensure the agent has a clear view
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Ensure focus is strictly on the application
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="