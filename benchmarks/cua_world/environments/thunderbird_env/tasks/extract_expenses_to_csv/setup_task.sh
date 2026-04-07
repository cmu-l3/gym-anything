#!/bin/bash
echo "=== Setting up extract_expenses_to_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents folder exists and clean up any old CSV
su - ga -c "mkdir -p /home/ga/Documents"
rm -f /home/ga/Documents/expense_summary.csv 2>/dev/null || true

# Thunderbird Profile paths
PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"

mkdir -p "$LOCAL_MAIL_DIR"
touch "$INBOX_FILE"

# Inject the 5 real-world messy emails into the Inbox mbox file
cat >> "$INBOX_FILE" << 'EOF'

From john.smith@company.com Mon Mar  1 10:00:00 2024
Date: Mon, 01 Mar 2024 10:00:00 +0000
From: John Smith <john.smith@company.com>
To: Finance <finance@company.com>
Subject: March Expense Report - John Smith

Please find my expense report for this month.
Department: Sales
Total requested: $1200.50

Best,
John

From alice.wong@company.com Tue Mar  2 11:30:00 2024
Date: Tue, 02 Mar 2024 11:30:00 +0000
From: Alice Wong <alice.wong@company.com>
To: Finance <finance@company.com>
Subject: Expense submission

Hi team, I'm submitting my expenses for the recent software licenses. I work in the Engineering department. The total comes out to 165.00 exactly. Let me know if you need the receipts.
Thanks, Alice Wong

From robert.chen@company.com Wed Mar  3 09:15:00 2024
Date: Wed, 03 Mar 2024 09:15:00 +0000
From: Robert Chen <robert.chen@company.com>
To: Finance <finance@company.com>
Subject: Marketing Expenses - R. Chen

Here is the breakdown:
Name: Robert Chen
Department: Marketing
| Item | Cost |
| Flights | 400.00 |
| Hotel | 450.75 |
---
Total Reimbursement: 850.75

From maria.garcia@company.com Thu Mar  4 14:20:00 2024
Date: Thu, 04 Mar 2024 14:20:00 +0000
From: Maria Garcia <maria.garcia@company.com>
To: Finance <finance@company.com>
Subject: HR offsite expense

Hello, this is Maria Garcia from HR. Please reimburse me for the team lunch which cost $45.20 in total.

From james.wilson@company.com Fri Mar  5 16:45:00 2024
Date: Fri, 05 Mar 2024 16:45:00 +0000
From: James Wilson <james.wilson@company.com>
To: Finance <finance@company.com>
Subject: Operations expense report

Hi, James Wilson here (Operations).
I have a few items to claim:
- Office supplies: $250
- Server cables: £200 (converted to $270)
Wait, never mind the cables, those were paid by the company card.
So just the supplies and a $70 transit pass.
My total requested reimbursement is $320.00.
EOF

# Ensure permissions are correct
chown -R ga:ga "$PROFILE_DIR"

# Delete MSF index file so Thunderbird rebuilds it and sees the new emails
rm -f "${INBOX_FILE}.msf" 2>/dev/null || true

# Start Thunderbird
start_thunderbird

# Wait for window
wait_for_thunderbird_window 30

# Maximize and focus
sleep 3
maximize_thunderbird

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="