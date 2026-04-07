#!/bin/bash
echo "=== Setting up save_emails_as_eml task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create the target CaseFiles directory
TARGET_DIR="/home/ga/Documents/CaseFiles"
mkdir -p "$TARGET_DIR"
chown -R ga:ga /home/ga/Documents

# Ensure Thunderbird is closed so we can inject into the mbox safely
close_thunderbird
sleep 2

INBOX_MBOX="/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
mkdir -p "$(dirname "$INBOX_MBOX")"

# Inject the 3 specific target emails (using valid RFC 2822 formatting)
cat >> "$INBOX_MBOX" << 'EOF'

From attorney@parkerfirm.com Thu Oct 10 14:23:07 2024
Return-Path: <attorney@parkerfirm.com>
Date: Thu, 10 Oct 2024 14:23:07 -0400
From: "Sarah K. Parker" <attorney@parkerfirm.com>
To: testuser@example.com
Subject: Re: Contract Amendment - Project Atlas Q4
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Dear Counsel,

Following our call this morning, I have reviewed the proposed amendment to
the Project Atlas master services agreement for Q4 2024. Our client is
prepared to accept the revised payment schedule outlined in Section 4.3,
subject to the conditions discussed.

Best regards,
Sarah K. Parker, Esq.

From mediator@bostonadr.org Fri Oct 11 09:45:33 2024
Return-Path: <mediator@bostonadr.org>
Date: Fri, 11 Oct 2024 09:45:33 -0400
From: "Hon. James R. Whitfield (Ret.)" <mediator@bostonadr.org>
To: testuser@example.com
Subject: Settlement Offer - Martinez v. Consolidated
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Counsel:

As mediator in the above-captioned matter, I am transmitting the
following settlement proposal from defendants Consolidated Holdings,
Inc. and Consolidated Property Management LLC:

Defendants offer to resolve all claims asserted in the Second Amended
Complaint (Docket No. 47) for the total sum of $375,000.

Respectfully,
Hon. James R. Whitfield (Ret.)

From paralegal@testuser-firm.com Mon Oct 14 16:12:08 2024
Return-Path: <paralegal@testuser-firm.com>
Date: Mon, 14 Oct 2024 16:12:08 -0400
From: "Diana Reyes" <paralegal@testuser-firm.com>
To: testuser@example.com
Subject: Discovery Documents - Case 2024-CV-1847
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Good afternoon,

I have completed the initial review of documents responsive to
Defendant's First Set of Requests for Production in Case No.
2024-CV-1847 (Martinez v. Consolidated Holdings, Inc.).

Summary of review:
  - Total documents reviewed:     1,247
  - Responsive, non-privileged:     683
  - Responsive, privileged:          89
  - Non-responsive:                 475

Best,
Diana Reyes
EOF

# Force rebuild of Thunderbird's index so the new emails appear immediately
rm -f "${INBOX_MBOX}.msf"
chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
start_thunderbird

# Wait for window, then maximize and focus
wait_for_thunderbird_window 30
sleep 3
maximize_thunderbird

# Take initial state screenshot for trajectory evidence
take_screenshot /tmp/task_initial.png ga
echo "Initial screenshot captured."

echo "=== Setup complete ==="