#!/bin/bash
# Setup script for legal_case_triage task
# Paralegal inbox organization task at Whitmore & Associates Law Firm

echo "=== Setting up legal_case_triage task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# STEP 1: Close Thunderbird to safely modify the mail database
# ============================================================
close_thunderbird
sleep 3
echo "Thunderbird closed for setup"

# ============================================================
# STEP 2: Remove any stale task output files BEFORE recording timestamp
# ============================================================
rm -f /tmp/legal_case_triage_result.json 2>/dev/null || true
rm -f /tmp/legal_case_triage_start_ts 2>/dev/null || true

# Remove pre-existing case folders if they exist (clean slate)
rm -f "${LOCAL_MAIL_DIR}/Cases" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Cases.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Cases.sbd" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Court_Notices" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Court_Notices.msf" 2>/dev/null || true

# ============================================================
# STEP 3: Inject 12 task-specific professional emails into Inbox
# Each email's sender/subject clearly identifies the case it belongs to
# (The agent must READ the email to determine correct routing)
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# --- Harrison v. Mercer emails (5 emails) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From david.harrison@personalmail.com Thu Jan 09 09:14:22 2025
From: David Harrison <david.harrison@personalmail.com>
To: jwhitmore@whitmore-law.com
Subject: Harrison case - timeline documents attached
Date: Thu, 09 Jan 2025 09:14:22 +0000
Message-ID: <harrison-001@personalmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

John,

I've gathered the performance review documents you requested for the Harrison v. Mercer proceeding. My previous manager completed these evaluations in Q3 and Q4 before the termination decision was made. I believe they clearly show the pretextual nature of the dismissal.

Should I bring the originals to your office, or is the scan sufficient for the discovery package?

David Harrison

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From jpreston@mercer-legal.com Thu Jan 09 11:02:55 2025
From: Janet Preston <jpreston@mercer-legal.com>
To: jwhitmore@whitmore-law.com
Subject: Harrison v. Mercer - Defendant's Initial Disclosures
Date: Thu, 09 Jan 2025 11:02:55 +0000
Message-ID: <harrison-002@mercer-legal.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Mr. Whitmore,

Pursuant to FRCP Rule 26(a), please find attached Defendant Mercer Industries' initial disclosures. As noted in Exhibit A, the performance improvement plan issued to Mr. Harrison in June preceded the employment decision by eight months. Defendant maintains the action was performance-based.

We expect reciprocal disclosures by January 24th.

Regards,
Janet Preston, Esq.
Mercer Industries Legal Counsel

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From courtclerk@district.court Thu Jan 09 13:30:00 2025
From: District Court Clerk <courtclerk@district.court>
To: jwhitmore@whitmore-law.com
Subject: Case 2025-CV-00147 Harrison v. Mercer - Scheduling Order
Date: Thu, 09 Jan 2025 13:30:00 +0000
Message-ID: <harrison-003@district.court>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

NOTICE OF SCHEDULING ORDER
Case No. 2025-CV-00147
Harrison v. Mercer Industries, Inc.

The Court has entered a scheduling order setting the following deadlines:
- Discovery cutoff: April 15, 2025
- Expert disclosures: March 1, 2025
- Dispositive motions: May 30, 2025
- Trial date: September 8, 2025

Counsel must appear for a status conference on February 3, 2025 at 10:00 AM.

District Court Clerk's Office

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From david.harrison@personalmail.com Fri Jan 10 08:45:00 2025
From: David Harrison <david.harrison@personalmail.com>
To: jwhitmore@whitmore-law.com
Subject: Re: Harrison case - witness list question
Date: Fri, 10 Jan 2025 08:45:00 +0000
Message-ID: <harrison-004@personalmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

John,

Regarding your question about witnesses — my former colleague Sandra Reyes was present at the January 15th meeting where the HR director made the comment about "cultural fit." She's willing to provide a declaration. Her contact is sreyes@gmail.com.

Also, I found the original offer letter you requested. I'm sending it by overnight mail today.

David

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From jpreston@mercer-legal.com Fri Jan 10 16:20:00 2025
From: Janet Preston <jpreston@mercer-legal.com>
To: jwhitmore@whitmore-law.com
Subject: Harrison v. Mercer - Deposition scheduling proposal
Date: Fri, 10 Jan 2025 16:20:00 +0000
Message-ID: <harrison-005@mercer-legal.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Mr. Whitmore,

We propose the following deposition schedule for the Harrison matter:
- HR Director Maria Gonzalez: February 10, 2025
- Division VP Thomas Crane: February 17, 2025
- Plaintiff David Harrison: February 24, 2025

Please confirm availability. We prefer a court reporter from Central Reporting Services.

Janet Preston, Esq.

MBOX_MSG

# --- DataVault Systems IP emails (4 emails) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From cto@datavaultsystems.com Thu Jan 09 10:00:00 2025
From: Kevin Tanaka <cto@datavaultsystems.com>
To: jwhitmore@whitmore-law.com
Subject: DataVault patent dispute - Innovatech claims
Date: Thu, 09 Jan 2025 10:00:00 +0000
Message-ID: <datavault-001@datavaultsystems.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

John,

I'm forwarding the cease-and-desist letter we received from Innovatech Corp alleging infringement of US Patent 10,847,291. Our distributed encryption module has been in development since 2019, which predates their filing date. We need prior art documentation prepared immediately.

Our engineering team can provide technical declarations. When can we schedule a call?

Kevin Tanaka
CTO, DataVault Systems

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From mwebb@hartleypatent.com Thu Jan 09 14:45:00 2025
From: Marcus Webb <mwebb@hartleypatent.com>
To: jwhitmore@whitmore-law.com
Subject: DataVault Systems / Innovatech - Demand for License Negotiation
Date: Thu, 09 Jan 2025 14:45:00 +0000
Message-ID: <datavault-002@hartleypatent.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Mr. Whitmore,

On behalf of Innovatech Corp, Hartley Patent Group hereby demands that DataVault Systems cease all infringement of US Patent 10,847,291 and enter into good-faith licensing negotiations. Our client has identified 14 specific feature implementations in DataVault's EncryptVault 3.x product line that directly read on Claims 1, 3, 7, and 12 of the referenced patent.

We are prepared to offer a reasonable royalty rate. Please respond within 14 days to avoid escalation to litigation.

Marcus Webb, J.D.
Senior Patent Counsel
Hartley Patent Group
mwebb@hartleypatent.com
+1 (312) 555-0193

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From examiner@uspto.gov Fri Jan 10 09:15:00 2025
From: USPTO Case Manager <examiner@uspto.gov>
To: jwhitmore@whitmore-law.com
Subject: Inter Partes Review Petition - DataVault / Patent 10847291
Date: Fri, 10 Jan 2025 09:15:00 +0000
Message-ID: <datavault-003@uspto.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

INTER PARTES REVIEW NOTICE
USPTO Patent Trial and Appeal Board

This is to confirm receipt of your Inter Partes Review petition for US Patent 10,847,291. The petition has been assigned Docket No. IPR2025-00422. The Patent Owner has 3 months from this notice to file a preliminary response.

Please direct all correspondence to IPR2025-00422@ptab.uspto.gov.

USPTO Patent Trial and Appeal Board

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From cto@datavaultsystems.com Fri Jan 10 15:30:00 2025
From: Kevin Tanaka <cto@datavaultsystems.com>
To: jwhitmore@whitmore-law.com
Subject: DataVault patent - engineer declaration ready for review
Date: Fri, 10 Jan 2025 15:30:00 +0000
Message-ID: <datavault-004@datavaultsystems.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

John,

Our lead engineer Dr. Sarah Park has completed her technical declaration establishing prior conception dates for the EncryptVault module. The lab notebook entries are dated March 2019, well before Innovatech's patent filing.

Please review the attached declaration and let us know if you need additional supporting documentation from our git commit history.

Kevin

MBOX_MSG

# --- Chen Family Estate emails (3 emails) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From linda.chen@gmail.com Thu Jan 09 15:00:00 2025
From: Linda Chen <linda.chen@gmail.com>
To: jwhitmore@whitmore-law.com
Subject: Mother's estate - questions about probate timeline
Date: Thu, 09 Jan 2025 15:00:00 +0000
Message-ID: <chen-001@gmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Mr. Whitmore,

Thank you for meeting with our family last week regarding our mother's estate. My brother Robert and I have a few questions:

1. How long will the probate process take given the two real estate properties?
2. The IRA beneficiary designation appears to name a predeceased relative — does that require court action?
3. Should we begin the appraisal process for the Riverside Drive property now?

We would appreciate a call at your earliest convenience.

Linda Chen

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From mpatel@estateaccounting.com Fri Jan 10 10:30:00 2025
From: Priya Patel <mpatel@estateaccounting.com>
To: jwhitmore@whitmore-law.com
Subject: Chen Estate - Inventory and Appraisal Coordination
Date: Fri, 10 Jan 2025 10:30:00 +0000
Message-ID: <chen-002@estateaccounting.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Mr. Whitmore,

Following our engagement as estate accountants for the Chen Estate matter, I am writing to coordinate the asset inventory. We have identified the following accounts requiring Letters Testamentary before transfer:

- Fidelity brokerage account (approx. $340,000)
- JP Morgan checking/savings ($82,000)
- Two real property deeds requiring probate court title transfer

We'll need certified copies of the Letters when available. Our valuation date will be the date of death: November 18, 2024.

Priya Patel, CPA
Estate Accounting Associates

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From courtclerk@district.court Fri Jan 10 14:00:00 2025
From: District Court Clerk <courtclerk@district.court>
To: jwhitmore@whitmore-law.com
Subject: Case 2025-PR-00089 In re Estate of Margaret Chen - Hearing Notice
Date: Fri, 10 Jan 2025 14:00:00 +0000
Message-ID: <chen-003@district.court>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

NOTICE OF PROBATE HEARING
Case No. 2025-PR-00089
In re Estate of Margaret Chen, Deceased

The Court has scheduled an Initial Probate Hearing for February 5, 2025 at 2:00 PM in Department 14. Please bring original Will and proposed petitioner identification.

District Court Clerk's Office

MBOX_MSG

# Set ownership
chown -R ga:ga "$INBOX_MBOX"
echo "Injected 12 legal case emails into Inbox"

# ============================================================
# STEP 4: Remove any pre-existing court notice filter to ensure clean baseline
# ============================================================
MSGFILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
if [ -f "$MSGFILTER_FILE" ]; then
    # Remove filters referencing courtclerk
    python3 << 'PYEOF'
import os
filter_file = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/msgFilterRules.dat")
if os.path.exists(filter_file):
    with open(filter_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    # Remove all entries — fresh start for this task
    with open(filter_file, 'w', encoding='utf-8') as f:
        f.write('version="9"\nlogging="no"\n')
    print("Cleaned filter rules file")
PYEOF
else
    mkdir -p "$(dirname $MSGFILTER_FILE)"
    echo 'version="9"' > "$MSGFILTER_FILE"
    echo 'logging="no"' >> "$MSGFILTER_FILE"
fi
chown ga:ga "$MSGFILTER_FILE" 2>/dev/null || true

# ============================================================
# STEP 5: Remove Marcus Webb from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        # Find cards with mwebb@hartleypatent.com and delete them
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%mwebb%'")
        cards = [r[0] for r in cur.fetchall()]
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Marcus Webb entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 6: Record baseline state AFTER all cleanup (anti-gaming)
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/legal_case_triage_inbox_baseline
date +%s > /tmp/legal_case_triage_start_ts
echo "Baseline inbox count: $INBOX_COUNT"
echo "Task start timestamp recorded"

# ============================================================
# STEP 7: Launch Thunderbird and wait for it to be ready
# ============================================================
start_thunderbird
wait_for_thunderbird_window 45
sleep 5
maximize_thunderbird
sleep 2

# Take initial screenshot
take_screenshot /tmp/legal_case_triage_start_screenshot.png
echo "Start screenshot saved"

echo "=== legal_case_triage setup complete ==="
echo "Inbox contains 12 emails from 3 legal cases — agent must read and route them"
