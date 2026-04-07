#!/bin/bash
echo "=== Setting up move_emails_to_folder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can safely manipulate mbox files
close_thunderbird
sleep 2

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"

mkdir -p "$LOCAL_MAIL_DIR"
touch "$INBOX_MBOX"

echo "Injecting target emails into Inbox..."

# Email 1
cat >> "$INBOX_MBOX" << 'EMAIL1'
From sarah.chen@acmefinancial.com Thu Sep 14 09:23:41 2024
Return-Path: <sarah.chen@acmefinancial.com>
From: Sarah Chen <sarah.chen@acmefinancial.com>
To: testuser@example.com
Subject: Q3 Budget Review - Marketing Department
Date: Thu, 14 Sep 2024 09:23:41 -0400
Message-ID: <budget-mktg-q3@acmefinancial.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Please find below the Q3 budget summary for the Marketing Department.
Total Spend: $281,100 vs. Budget of $306,000.
EMAIL1
echo "" >> "$INBOX_MBOX"

# Email 2
cat >> "$INBOX_MBOX" << 'EMAIL2'
From sarah.chen@acmefinancial.com Fri Sep 15 14:07:22 2024
Return-Path: <sarah.chen@acmefinancial.com>
From: Sarah Chen <sarah.chen@acmefinancial.com>
To: testuser@example.com
Subject: Q3 Budget Review - Engineering Costs
Date: Fri, 15 Sep 2024 14:07:22 -0400
Message-ID: <budget-eng-q3@acmefinancial.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Q3 Engineering cost analysis is complete.
Total Q3 Engineering: $1,284,200 vs. Budget of $1,247,000.
EMAIL2
echo "" >> "$INBOX_MBOX"

# Email 3
cat >> "$INBOX_MBOX" << 'EMAIL3'
From sarah.chen@acmefinancial.com Mon Sep 18 10:45:03 2024
Return-Path: <sarah.chen@acmefinancial.com>
From: Sarah Chen <sarah.chen@acmefinancial.com>
To: testuser@example.com
Subject: Q3 Budget Review - Sales Projections
Date: Mon, 18 Sep 2024 10:45:03 -0400
Message-ID: <budget-sales-q3@acmefinancial.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Q3 Sales budget review with revenue projection analysis.
Total Q3 Sales Expense: $854,500 vs. Budget of $867,900.
EMAIL3
echo "" >> "$INBOX_MBOX"

# Email 4
cat >> "$INBOX_MBOX" << 'EMAIL4'
From sarah.chen@acmefinancial.com Tue Sep 19 16:32:18 2024
Return-Path: <sarah.chen@acmefinancial.com>
From: Sarah Chen <sarah.chen@acmefinancial.com>
To: testuser@example.com
Subject: Q3 Budget Review - Operations Summary
Date: Tue, 19 Sep 2024 16:32:18 -0400
Message-ID: <budget-ops-q3@acmefinancial.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Operations Q3 budget summary is ready.
Total Q3 Operations: $467,100 vs. Budget of $489,000.
EMAIL4
echo "" >> "$INBOX_MBOX"

# Email 5
cat >> "$INBOX_MBOX" << 'EMAIL5'
From sarah.chen@acmefinancial.com Wed Sep 20 11:15:55 2024
Return-Path: <sarah.chen@acmefinancial.com>
From: Sarah Chen <sarah.chen@acmefinancial.com>
To: testuser@example.com
Subject: Q3 Budget Review - HR and Recruiting
Date: Wed, 20 Sep 2024 11:15:55 -0400
Message-ID: <budget-hr-q3@acmefinancial.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Final department review - HR and Recruiting Q3 budget.
Total Q3 HR: $411,200 vs. Budget of $404,500.
EMAIL5
echo "" >> "$INBOX_MBOX"

# Create empty target folder (0 bytes representing empty mbox)
BUDGET_FOLDER="${LOCAL_MAIL_DIR}/Budget_Reviews"
> "$BUDGET_FOLDER"

# Clear Thunderbird index files to force it to rebuild the folder caches
rm -f "${LOCAL_MAIL_DIR}/"*.msf 2>/dev/null || true

# Set correct permissions
chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
start_thunderbird

if wait_for_thunderbird_window 30; then
    maximize_thunderbird
    sleep 2
fi

# Take initial screenshot showing Thunderbird with emails loaded
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="