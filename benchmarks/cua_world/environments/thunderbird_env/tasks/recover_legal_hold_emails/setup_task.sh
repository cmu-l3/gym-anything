#!/bin/bash
set -euo pipefail

echo "=== Setting up recover_legal_hold_emails task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can safely modify mbox files
close_thunderbird
sleep 2

LOCAL_MAIL_DIR="/home/ga/.thunderbird/default-release/Mail/Local Folders"
TRASH_FILE="${LOCAL_MAIL_DIR}/Trash"

# Remove any existing Legal_Hold folder
rm -f "${LOCAL_MAIL_DIR}/Legal_Hold"
rm -f "${LOCAL_MAIL_DIR}/Legal_Hold.msf"

# Force rebuild of Trash msf by deleting it
rm -f "${LOCAL_MAIL_DIR}/Trash.msf"

# Ensure Trash exists
touch "$TRASH_FILE"

# Inject 4 specific realistic Acme emails into Trash
# X-Mozilla-Status: 0009 means Read (0001) + Deleted (0008)
cat >> "$TRASH_FILE" << 'EOF'

From - Mon Oct 23 09:15:00 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "David Partner" <dpartner@lawfirm.com>
To: "Associate Team" <associates@lawfirm.com>
Subject: Urgent: Acme Corp Merger Due Diligence
Date: Mon, 23 Oct 2023 09:15:00 -0400
Message-ID: <acme-merger-1@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Team, we need to finalize the due diligence report for the Acme Corp merger by Friday. Please review the attached financials.

From - Tue Oct 24 11:22:33 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "Sarah Legal" <sarah@lawfirm.com>
To: "Associate Team" <associates@lawfirm.com>
Subject: Re: Acme Corp Merger - IP Assets
Date: Tue, 24 Oct 2023 11:22:33 -0400
Message-ID: <acme-merger-2@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

I've reviewed the intellectual property portfolio for Acme. There are a few outstanding patents we need clarification on.

From - Wed Oct 25 14:45:10 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "Compliance Dept" <compliance@lawfirm.com>
To: "David Partner" <dpartner@lawfirm.com>
Subject: Acme Corp - Regulatory Approval Update
Date: Wed, 25 Oct 2023 14:45:10 -0400
Message-ID: <acme-merger-3@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

The FTC has acknowledged receipt of our filing regarding the Acme acquisition. We anticipate a 30-day waiting period.

From - Thu Oct 26 16:30:00 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "HR Department" <hr@acmecorp.com>
To: "David Partner" <dpartner@lawfirm.com>
Subject: Acme Employee Transition Plan
Date: Thu, 26 Oct 2023 16:30:00 -0400
Message-ID: <acme-merger-4@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Attached is the preliminary employee transition matrix for Acme Corp staff post-merger.
EOF

# Inject a couple of noise emails to ensure agent has to filter
cat >> "$TRASH_FILE" << 'EOF'

From - Fri Oct 27 10:00:00 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "Lunch Committee" <lunch@lawfirm.com>
To: "All Staff" <all@lawfirm.com>
Subject: Friday Pizza Count
Date: Fri, 27 Oct 2023 10:00:00 -0400
Message-ID: <noise-1@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Please let us know if you want pepperoni or cheese.

From - Fri Oct 27 11:00:00 2023
X-Mozilla-Status: 0009
X-Mozilla-Status2: 00000000
From: "IT Desk" <it@lawfirm.com>
To: "All Staff" <all@lawfirm.com>
Subject: Scheduled Server Maintenance
Date: Fri, 27 Oct 2023 11:00:00 -0400
Message-ID: <noise-2@lawfirm.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Servers will be down from 2 AM to 4 AM this Sunday.
EOF

# Fix permissions
chown -R ga:ga /home/ga/.thunderbird

# Start Thunderbird
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize and focus the window
maximize_thunderbird
sleep 1
WID=$(get_thunderbird_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="