#!/bin/bash
# Setup script for financial_audit_prep task
# Financial Controller at Meridian Capital Partners — SEC/FINRA regulatory exam inbox organization

echo "=== Setting up financial_audit_prep task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# STEP 1: Close Thunderbird to safely modify the mail database
# ============================================================
close_thunderbird
sleep 3
echo "Thunderbird closed for setup"

# ============================================================
# STEP 2: Remove stale task files BEFORE recording timestamp
# ============================================================
rm -f /tmp/financial_audit_prep_result.json 2>/dev/null || true
rm -f /tmp/financial_audit_prep_start_ts 2>/dev/null || true
rm -f /tmp/financial_audit_prep_inbox_baseline 2>/dev/null || true
rm -f /tmp/financial_audit_prep_abook_check.json 2>/dev/null || true

# Remove pre-existing regulatory folders (clean slate)
rm -f "${LOCAL_MAIL_DIR}/Regulatory" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Regulatory.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Regulatory.sbd" 2>/dev/null || true

# ============================================================
# STEP 3: Inject 9 professional emails into Inbox
# 4 SEC examination emails + 3 FINRA review emails + 2 internal
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# --- SEC Examination emails (4 emails from @sec.gov) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From jkowalski@sec.gov Mon Mar 04 08:15:00 2024
From: Jennifer Kowalski <jkowalski@sec.gov>
To: jreeves@meridiancp.com
Subject: Examination Notice - Meridian Capital Partners - SEC Exam #2024-NY-0847
Date: Mon, 04 Mar 2024 08:15:00 -0500
Message-ID: <sec-001@sec.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

This letter is to inform you that the Securities and Exchange Commission, New York Regional Office, has selected Meridian Capital Partners, LLC for a routine examination pursuant to Section 204 of the Investment Advisers Act of 1940. The examination has been assigned Reference Number 2024-NY-0847.

The examination team will review books and records covering the period January 1, 2022 through December 31, 2023. We will contact you within 5 business days with an initial document request list.

Please designate a primary contact person to coordinate with the examination team.

Jennifer Kowalski
Senior Examination Manager
SEC Office of Compliance Inspections and Examinations
New York Regional Office
jkowalski@sec.gov | (212) 336-1100

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From jkowalski@sec.gov Tue Mar 05 10:30:00 2024
From: Jennifer Kowalski <jkowalski@sec.gov>
To: jreeves@meridiancp.com
Subject: Document Request List No. 1 - Examination #2024-NY-0847
Date: Tue, 05 Mar 2024 10:30:00 -0500
Message-ID: <sec-002@sec.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

Pursuant to the above-referenced examination, we request the following documents by March 15, 2024:

1. Form ADV Parts 1, 2A, and 2B (current and all amendments)
2. Compliance manual and annual review reports (2022-2023)
3. Code of Ethics and all reported violations/certifications
4. List of all investment advisory clients with AUM as of December 31, 2023
5. Copies of all client agreements executed during the review period
6. Policies and procedures for best execution

Documents may be produced electronically to our secure upload portal. Access credentials will follow under separate cover.

Jennifer Kowalski
Senior Examination Manager | SEC OCIE New York

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From sfletcher@sec.gov Wed Mar 06 14:45:00 2024
From: Samuel Fletcher <sfletcher@sec.gov>
To: jreeves@meridiancp.com
Subject: Net Capital Calculations - Examination #2024-NY-0847 - Supplemental Request
Date: Wed, 06 Mar 2024 14:45:00 -0500
Message-ID: <sec-003@sec.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

I am a member of the examination team for Exam #2024-NY-0847 led by Jennifer Kowalski. As part of our financial review, please provide the following supplemental documentation:

1. Monthly FOCUS reports for all 24 months of the review period
2. Net capital computations as of December 31, 2022 and December 31, 2023
3. Aggregate indebtedness calculations with supporting workpapers
4. List of customer credits and debits for net capital purposes

The above documents should be uploaded to the portal no later than March 18, 2024.

Samuel Fletcher
Examination Staff Accountant | SEC OCIE New York
sfletcher@sec.gov

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From jkowalski@sec.gov Thu Mar 07 09:00:00 2024
From: Jennifer Kowalski <jkowalski@sec.gov>
To: jreeves@meridiancp.com
Subject: On-Site Examination Confirmation - Week of March 18-22, 2024
Date: Thu, 07 Mar 2024 09:00:00 -0500
Message-ID: <sec-004@sec.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

This email confirms the on-site phase of SEC Examination #2024-NY-0847 at your offices during the week of March 18-22, 2024. Our team of three examiners will arrive Monday March 18 at 9:00 AM.

Please ensure the following are available upon arrival:
- A dedicated workspace with network access
- Access to your portfolio management and trading systems
- Availability of your Chief Compliance Officer and CFO for interviews
- All documents from Document Request No. 1 in electronic or hard copy form

If any scheduling conflicts arise, please contact me immediately.

Jennifer Kowalski
Senior Examination Manager | SEC OCIE New York

MBOX_MSG

# --- FINRA Review emails (3 emails from @finra.org) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dcarter@finra.org Mon Mar 04 11:20:00 2024
From: David Carter <dcarter@finra.org>
To: jreeves@meridiancp.com
Subject: FINRA Net Capital Review - Case FR-2024-NY-0312 - Initiation Notice
Date: Mon, 04 Mar 2024 11:20:00 -0500
Message-ID: <finra-001@finra.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

FINRA has selected Meridian Capital Partners for a targeted Net Capital Review under FINRA Rule 4110 and SEC Rule 15c3-1. This review has been assigned Case Number FR-2024-NY-0312.

The review will focus on your firm's net capital computations for the periods ending September 30, 2023 and December 31, 2023. We will require access to your books and records, including trial balances, aged receivables schedules, and haircut calculations.

A preliminary document request will follow within 3 business days.

David Carter
Principal Examiner — Financial Surveillance
FINRA Department of Member Supervision
dcarter@finra.org | (212) 858-4400

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From lhoffman@finra.org Wed Mar 06 13:00:00 2024
From: Lisa Hoffman <lhoffman@finra.org>
To: jreeves@meridiancp.com
Subject: Rule 15c3-1 Compliance Documentation Request - Case FR-2024-NY-0312
Date: Wed, 06 Mar 2024 13:00:00 -0500
Message-ID: <finra-002@finra.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

Further to the initiation notice from David Carter regarding Case FR-2024-NY-0312, please provide the following documentation by March 14, 2024:

1. Net capital computations as of September 30 and December 31, 2023 (FOCUS Part II/IIA)
2. Subordinated loan agreements in place during review period
3. Organizational chart showing entities included in net capital computation
4. Proprietary trading records and related haircut calculations
5. List of all bank accounts and current balances

Please submit to our secure portal using the case number as the reference.

Lisa Hoffman
Examiner — Financial Surveillance
FINRA Department of Member Supervision
lhoffman@finra.org

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dcarter@finra.org Fri Mar 08 15:30:00 2024
From: David Carter <dcarter@finra.org>
To: jreeves@meridiancp.com
Subject: FINRA On-Site Visit Schedule - Case FR-2024-NY-0312
Date: Fri, 08 Mar 2024 15:30:00 -0500
Message-ID: <finra-003@finra.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Ms. Reeves,

FINRA examination team for Case FR-2024-NY-0312 will conduct an on-site visit to your offices on March 25-26, 2024. The team will consist of myself and two additional examiners.

During the visit, we will require:
- Access to your trading system and position records
- Interview with the Chief Financial Officer (approximately 2 hours)
- Access to original source documents for any items flagged during document review

Please confirm receipt of this notice and your availability for the scheduled visit. If there are conflicts, contact me immediately at (212) 858-4400.

David Carter
Principal Examiner — Financial Surveillance | FINRA

MBOX_MSG

# --- Internal emails (2 emails — should remain in Inbox) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From compliance@meridiancp.com Tue Mar 05 09:00:00 2024
From: Compliance Department <compliance@meridiancp.com>
To: jreeves@meridiancp.com
Subject: Q4 2023 Annual Compliance Review - Action Items
Date: Tue, 05 Mar 2024 09:00:00 -0500
Message-ID: <internal-001@meridiancp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Jennifer,

Following last week's annual compliance review, the following action items require your attention before the end of March:

1. Update the business continuity plan to reflect last year's office relocation
2. Document the rationale for Q4 soft dollar arrangements
3. Confirm personal trading pre-clearance records are complete for all supervised persons

Please coordinate with the CCO's office by March 22.

Compliance Department
Meridian Capital Partners

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From cfoteam@meridiancp.com Thu Mar 07 16:00:00 2024
From: Finance Team <cfoteam@meridiancp.com>
To: jreeves@meridiancp.com
Subject: Monthly Finance Team Standup - March 20 Agenda
Date: Thu, 07 Mar 2024 16:00:00 -0500
Message-ID: <internal-002@meridiancp.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi Jennifer,

Agenda items for the March 20 team standup:

1. Q1 2024 budget variance review
2. Accounts payable aging report
3. Examination preparation status update (placeholder — Jennifer to lead)
4. Technology spend allocation for Q2

Meeting at 10 AM in the main conference room. Dial-in details in the calendar invite.

Finance Team

MBOX_MSG

chown -R ga:ga "$INBOX_MBOX"
echo "Injected 9 regulatory/financial emails into Inbox"

# ============================================================
# STEP 4: Remove any pre-existing filters to ensure clean baseline
# ============================================================
MSGFILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
python3 << 'PYEOF'
import os
filter_file = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/msgFilterRules.dat")
os.makedirs(os.path.dirname(filter_file), exist_ok=True)
with open(filter_file, 'w', encoding='utf-8') as f:
    f.write('version="9"\nlogging="no"\n')
print("Cleaned filter rules file")
PYEOF
chown ga:ga "$MSGFILTER_FILE" 2>/dev/null || true

# ============================================================
# STEP 5: Remove Jennifer Kowalski from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%jkowalski%'")
        cards = [r[0] for r in cur.fetchall()]
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Jennifer Kowalski entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 6: Record baseline AFTER all cleanup (anti-gaming)
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/financial_audit_prep_inbox_baseline
date +%s > /tmp/financial_audit_prep_start_ts
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

take_screenshot /tmp/financial_audit_prep_start_screenshot.png
echo "Start screenshot saved"

echo "=== financial_audit_prep setup complete ==="
echo "Inbox contains 9 emails: 4 SEC + 3 FINRA + 2 internal — agent must route regulatory emails to correct folders"
