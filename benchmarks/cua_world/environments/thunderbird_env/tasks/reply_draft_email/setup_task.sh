#!/bin/bash
echo "=== Setting up reply_draft_email task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Close Thunderbird if running so we can safely modify mbox files
close_thunderbird
sleep 2

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
DRAFTS_MBOX="${LOCAL_MAIL_DIR}/Drafts"
SENT_MBOX="${LOCAL_MAIL_DIR}/Sent"

# Ensure directories and files exist
mkdir -p "$LOCAL_MAIL_DIR"
touch "$INBOX_MBOX"
touch "$DRAFTS_MBOX"
touch "$SENT_MBOX"

# Record initial Drafts and Sent state for anti-gaming
INITIAL_DRAFT_COUNT=$(grep -c "^From " "$DRAFTS_MBOX" 2>/dev/null || echo "0")
echo "$INITIAL_DRAFT_COUNT" > /tmp/initial_draft_count.txt

INITIAL_SENT_COUNT=$(grep -c "^From " "$SENT_MBOX" 2>/dev/null || echo "0")
echo "$INITIAL_SENT_COUNT" > /tmp/initial_sent_count.txt

# Inject the target customer inquiry email into the Inbox
cat >> "$INBOX_MBOX" << 'EMAILEOF'
From marcus.chen@pacificrim-supply.com Thu Nov 14 09:23:17 2024
Return-Path: <marcus.chen@pacificrim-supply.com>
Delivered-To: testuser@example.com
Received: from mail.pacificrim-supply.com (mail.pacificrim-supply.com [203.0.113.45])
    by mx.example.com (Postfix) with ESMTPS id 4X8kLm2nRqz9vBT
    for <testuser@example.com>; Thu, 14 Nov 2024 09:23:17 -0800 (PST)
From: Marcus Chen <marcus.chen@pacificrim-supply.com>
To: testuser@example.com
Subject: Product Availability Inquiry - Industrial Fasteners
Date: Thu, 14 Nov 2024 09:23:17 -0800
Message-ID: <20241114092317.ABC123@pacificrim-supply.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 7bit

Hi,

I'm reaching out from Pacific Rim Supply Co. regarding our Q1 2025
procurement planning. We're currently evaluating suppliers for several
categories of industrial fasteners and would appreciate your help with
the following:

1. M10 hex bolts, Grade 8.8, zinc-plated - We need approximately
   12,000-15,000 units. Could you confirm current stock levels?

2. M8 carriage bolts, Grade 5, hot-dip galvanized - We're looking at
   around 8,000 units. Are these available for immediate dispatch?

For both items, we would need:
- Current per-unit pricing
- Any volume discount tiers available
- Estimated delivery timeline to our Portland, OR warehouse

We've been sourcing from Midwest Bolt & Nut but are looking to
diversify our supply chain after some recent lead time issues.

Our target is to have purchase orders finalized by end of November,
so a prompt response would be greatly appreciated.

Best regards,
Marcus Chen
Senior Procurement Manager
Pacific Rim Supply Co.

EMAILEOF

echo "" >> "$INBOX_MBOX"

# Fix permissions
chown -R ga:ga "$PROFILE_DIR"

# Remove stale .msf index files so Thunderbird rebuilds them
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Drafts.msf" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Sent.msf" 2>/dev/null || true

# Start Thunderbird
echo "Starting Thunderbird..."
start_thunderbird

# Wait for window to appear
if wait_for_thunderbird_window 30; then
    echo "Thunderbird window detected"
    maximize_thunderbird
    sleep 2
else
    echo "WARNING: Thunderbird window not detected within timeout"
fi

# Dismiss any popup dialogs that might block the UI
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot of the starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="