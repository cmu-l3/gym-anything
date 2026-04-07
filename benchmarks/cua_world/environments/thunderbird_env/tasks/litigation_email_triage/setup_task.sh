#!/bin/bash
# Setup script for litigation_email_triage task
# Paralegal at Whitmore & Associates — Meridian Corp v. Apex Industries litigation
#
# This task injects 15 emails with intentionally generic subjects so the agent
# must read email bodies to determine correct folder routing. Key design:
# - Rebecca Torres (r.torres@kline-harris.com) has emails in BOTH Pleadings and Discovery
# - Marcus Chen (m.chen@whitmorelaw.com) has emails in BOTH Pleadings and Discovery
# - This prevents sender-based routing shortcuts

echo "=== Setting up litigation_email_triage task ==="

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
rm -f /tmp/litigation_email_triage_result.json 2>/dev/null || true
rm -f /tmp/litigation_email_triage_start_ts 2>/dev/null || true
rm -f /tmp/litigation_email_triage_inbox_baseline 2>/dev/null || true
rm -f /tmp/litigation_email_triage_abook_check.json 2>/dev/null || true
rm -f /tmp/litigation_email_triage_draft_check.json 2>/dev/null || true
rm -f /tmp/litigation_email_triage_filter_check.json 2>/dev/null || true

# Remove pre-existing case folders (clean slate)
rm -f "${LOCAL_MAIL_DIR}/Meridian_v_Apex" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Meridian_v_Apex.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Meridian_v_Apex.sbd" 2>/dev/null || true
# Also remove variant names
for variant in Meridian Meridian_Apex MeridianApex Meridian-v-Apex; do
    rm -f "${LOCAL_MAIL_DIR}/${variant}" 2>/dev/null || true
    rm -f "${LOCAL_MAIL_DIR}/${variant}.msf" 2>/dev/null || true
    rm -rf "${LOCAL_MAIL_DIR}/${variant}.sbd" 2>/dev/null || true
done

# ============================================================
# STEP 3: Inject 15 litigation emails into Inbox
#
# Distribution:
#   5 Pleadings (court filings and motions)
#   5 Discovery (document requests, depositions, interrogatories)
#   3 Billing   (invoices and cost reports)
#   2 Non-case  (firm announcements — should stay in Inbox)
#
# Cross-category senders (force content-based routing):
#   r.torres@kline-harris.com → 2 Pleadings + 2 Discovery
#   m.chen@whitmorelaw.com    → 1 Pleadings + 1 Discovery
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# ---------------------------------------------------------------
# PLEADINGS EMAIL 1: Torres — Motion to dismiss (generic subject)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From r.torres@kline-harris.com Mon Feb 03 09:15:00 2025
From: Rebecca Torres <r.torres@kline-harris.com>
To: paralegal@whitmorelaw.com
Subject: Re: Pending Matters
Date: Mon, 03 Feb 2025 09:15:00 -0500
Message-ID: <lit-pleading-001@kline-harris.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Counsel,

Pursuant to FRCP Rule 12(b)(6), we are filing a Motion to Dismiss Count III of the Amended Complaint in Meridian Corp v. Apex Industries. Our position is that the tortious interference claim fails to state a cause of action because no independent duty exists outside the contractual relationship.

We will submit the motion brief to the Court by February 14. Please confirm whether Whitmore & Associates intends to file an opposition brief or rely on the existing record.

Rebecca Torres, Esq.

MBOX_MSG

# ---------------------------------------------------------------
# PLEADINGS EMAIL 2: Torres — Amended complaint (generic subject)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From r.torres@kline-harris.com Tue Feb 04 14:30:00 2025
From: Rebecca Torres <r.torres@kline-harris.com>
To: paralegal@whitmorelaw.com
Subject: Updated Filing
Date: Tue, 04 Feb 2025 14:30:00 -0500
Message-ID: <lit-pleading-002@kline-harris.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Counsel,

Attached is Apex Industries' Amended Answer and Counterclaim filed today with the Court. We have added a counterclaim for breach of the implied covenant of good faith and fair dealing (Count IV) and are seeking damages in excess of $2.4 million.

The revised exhibit list reflecting these amendments is enclosed. Please update your trial preparation materials accordingly.

Rebecca Torres, Esq.
Senior Partner | Kline & Harris LLP

MBOX_MSG

# ---------------------------------------------------------------
# PLEADINGS EMAIL 3: Chen (internal) — Draft motion to compel
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From m.chen@whitmorelaw.com Wed Feb 05 10:00:00 2025
From: Marcus Chen <m.chen@whitmorelaw.com>
To: paralegal@whitmorelaw.com
Subject: Draft for Review
Date: Wed, 05 Feb 2025 10:00:00 -0500
Message-ID: <lit-pleading-003@whitmorelaw.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi,

I have completed the draft Motion to Compel Production of Documents in the Meridian v. Apex matter. Apex has failed to produce the internal audit reports referenced in their 10-K filing despite our Second Request for Production served on January 10.

Please review the draft brief and supporting declaration before I route it to the partner for signature. The filing deadline with Judge Okonkwo is February 21.

Thanks,
Marcus Chen
Associate Attorney, Whitmore & Associates

MBOX_MSG

# ---------------------------------------------------------------
# PLEADINGS EMAIL 4: Court clerk — Scheduling conference notice
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From clerk@district-court.gov Thu Feb 06 13:30:00 2025
From: District Court Clerk <clerk@district-court.gov>
To: paralegal@whitmorelaw.com
Subject: Notice - Case #2024-CV-0489
Date: Thu, 06 Feb 2025 13:30:00 -0500
Message-ID: <lit-pleading-004@district-court.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

NOTICE OF SCHEDULING CONFERENCE
Case No. 2024-CV-0489
Meridian Corp v. Apex Industries, Inc.

The Court has scheduled a status conference for March 5, 2025 at 10:00 AM in Courtroom 14B before the Honorable Judge Adaeze Okonkwo.

Counsel for all parties must appear. Topics include the pending Motion to Dismiss and the proposed amended scheduling order.

District Court Clerk's Office

MBOX_MSG

# ---------------------------------------------------------------
# PLEADINGS EMAIL 5: Court clerk — Judge's order
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From clerk@district-court.gov Fri Feb 07 11:00:00 2025
From: District Court Clerk <clerk@district-court.gov>
To: paralegal@whitmorelaw.com
Subject: Order
Date: Fri, 07 Feb 2025 11:00:00 -0500
Message-ID: <lit-pleading-005@district-court.gov>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

ORDER ON DEFENDANT'S MOTION IN LIMINE
Case No. 2024-CV-0489
Meridian Corp v. Apex Industries, Inc.

The Court has reviewed Defendant's Motion in Limine to exclude expert testimony from Dr. Patricia Hwang regarding damages methodology.

IT IS HEREBY ORDERED that the motion is DENIED. The Court finds the testimony relevant under FRE 702 and Daubert. Dr. Hwang may testify at trial subject to cross-examination.

SO ORDERED this 7th day of February, 2025.

Hon. Adaeze Okonkwo
United States District Judge

MBOX_MSG

# ---------------------------------------------------------------
# DISCOVERY EMAIL 1: Torres — Interrogatories (generic subject)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From r.torres@kline-harris.com Mon Feb 10 09:00:00 2025
From: Rebecca Torres <r.torres@kline-harris.com>
To: paralegal@whitmorelaw.com
Subject: Re: Follow-up
Date: Mon, 10 Feb 2025 09:00:00 -0500
Message-ID: <lit-discovery-001@kline-harris.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Counsel,

Enclosed please find Defendant Apex Industries' First Set of Interrogatories to Plaintiff Meridian Corp, consisting of 25 interrogatories pursuant to FRCP Rule 33. These interrogatories relate to Meridian's corporate structure, revenue attribution methodology, and the specific contractual provisions at issue.

Responses are due within 30 days of service. Please direct any meet-and-confer requests to my associate Kevin Zhang.

Rebecca Torres, Esq.
Senior Partner | Kline & Harris LLP
r.torres@kline-harris.com
Direct: (555) 234-5678

MBOX_MSG

# ---------------------------------------------------------------
# DISCOVERY EMAIL 2: Torres — Supplemental document request
# (THIS IS THE EMAIL THE AGENT SHOULD REPLY TO)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From r.torres@kline-harris.com Wed Feb 12 15:45:00 2025
From: Rebecca Torres <r.torres@kline-harris.com>
To: paralegal@whitmorelaw.com
Subject: Additional Items Needed
Date: Wed, 12 Feb 2025 15:45:00 -0500
Message-ID: <lit-discovery-002@kline-harris.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Counsel,

We are submitting a Supplemental Request for Production of Documents in the Meridian v. Apex matter. Specifically, we request complete and unredacted copies of:

1. All Board of Directors meeting minutes from January 2022 through December 2024
2. Internal audit committee reports for the same period
3. All communications between Meridian executives and Apex Industries representatives regarding the supply agreement at issue

Please produce these documents by March 28, 2025, consistent with the Court's amended scheduling order.

Rebecca Torres, Esq.
Senior Partner | Kline & Harris LLP
r.torres@kline-harris.com
Direct: (555) 234-5678

MBOX_MSG

# ---------------------------------------------------------------
# DISCOVERY EMAIL 3: Chen (internal) — Deposition prep (generic subject)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From m.chen@whitmorelaw.com Thu Feb 13 11:30:00 2025
From: Marcus Chen <m.chen@whitmorelaw.com>
To: paralegal@whitmorelaw.com
Subject: FYI - Next Week
Date: Thu, 13 Feb 2025 11:30:00 -0500
Message-ID: <lit-discovery-003@whitmorelaw.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi,

Wanted to give you a heads-up that I am finalizing the deposition preparation outline for Dr. Patricia Hwang, our damages expert in the Meridian v. Apex case. We need to prepare her for cross-examination on her lost-profits methodology.

Key areas to cover: market share data sources, discount rate assumptions, and the mitigation analysis. Can you pull the relevant exhibits from the document production binder by next Tuesday?

Thanks,
Marcus

MBOX_MSG

# ---------------------------------------------------------------
# DISCOVERY EMAIL 4: Zhang (paralegal) — Deposition logistics
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From k.zhang@kline-harris.com Mon Feb 17 10:15:00 2025
From: Kevin Zhang <k.zhang@kline-harris.com>
To: paralegal@whitmorelaw.com
Subject: Quick Question
Date: Mon, 17 Feb 2025 10:15:00 -0500
Message-ID: <lit-discovery-004@kline-harris.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi,

I am coordinating the deposition logistics for the Meridian v. Apex matter. We have confirmed the court reporter from National Reporting Group and need to finalize the following:

- Deposition of CFO James Whitfield: March 10, 2025 at 9:30 AM
- Deposition of VP of Operations Linda Park: March 12, 2025 at 1:00 PM
- Video equipment has been reserved for both sessions

Can you confirm your team's availability for these dates? We will need the conference room at your office for the Whitfield deposition.

Kevin Zhang
Senior Paralegal | Kline & Harris LLP

MBOX_MSG

# ---------------------------------------------------------------
# DISCOVERY EMAIL 5: Apex Industries — Subpoena response
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From records@apex-industries.com Tue Feb 18 16:00:00 2025
From: Records Department <records@apex-industries.com>
To: paralegal@whitmorelaw.com
Subject: Re: Your Request
Date: Tue, 18 Feb 2025 16:00:00 -0500
Message-ID: <lit-discovery-005@apex-industries.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

To Whom It May Concern,

In response to the Subpoena Duces Tecum served on Apex Industries on January 28, 2025, we are producing documents responsive to Categories 1, 2, and 4 of the subpoena schedule. Documents for Categories 3 and 5 are being withheld pending a privilege review by outside counsel.

A privilege log will be provided within 14 days as required by FRCP Rule 45(e)(2). The responsive documents (Bates numbered APEX-00001 through APEX-02847) are available for download via the secure document portal. Access credentials will follow under separate cover.

Records Management
Apex Industries, Inc.

MBOX_MSG

# ---------------------------------------------------------------
# BILLING EMAIL 1: LegalCosts — Monthly cost statement
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From accounting@legalcosts.com Wed Feb 19 09:00:00 2025
From: Accounting Department <accounting@legalcosts.com>
To: paralegal@whitmorelaw.com
Subject: Monthly Statement
Date: Wed, 19 Feb 2025 09:00:00 -0500
Message-ID: <lit-billing-001@legalcosts.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Whitmore & Associates
Meridian Corp v. Apex Industries — Case Cost Summary
Statement Period: January 2025

Litigation Support Services:
  Expert witness fees (Dr. Hwang, consulting):     $12,500.00
  Court filing fees:                                 $1,850.00
  Court reporter services (3 hearings):              $4,200.00
  Process server fees:                                 $375.00
  Westlaw/LexisNexis research charges:               $2,825.00

Document Management:
  E-discovery hosting (247 GB active):              $18,500.00
  Document review contractor hours (160 hrs):        $7,000.00

Total This Period:                                  $47,250.00
Year-to-Date Total:                                $183,475.00

Payment due within 30 days. Questions: accounting@legalcosts.com

MBOX_MSG

# ---------------------------------------------------------------
# BILLING EMAIL 2: LegalCosts — E-discovery vendor invoice
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From j.patel@legalcosts.com Thu Feb 20 14:30:00 2025
From: Jenna Patel <j.patel@legalcosts.com>
To: paralegal@whitmorelaw.com
Subject: Invoice #2024-0891
Date: Thu, 20 Feb 2025 14:30:00 -0500
Message-ID: <lit-billing-002@legalcosts.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Whitmore & Associates,

Please find attached Invoice #2024-0891 for e-discovery services rendered in the Meridian Corp v. Apex Industries matter during the period January 15 - February 15, 2025.

Service Details:
  Document review platform license (RelativityOne):  $8,200.00
  TAR (Technology-Assisted Review) processing:       $3,400.00
  Data collection and forensic imaging:              $2,800.00
  Project management (42 hours @ $125/hr):           $1,400.00

Invoice Total:                                      $15,800.00
Payment Terms: Net-30 from invoice date

For questions regarding this invoice, please contact me directly.

Jenna Patel
Senior Account Manager | LegalCosts Solutions
j.patel@legalcosts.com

MBOX_MSG

# ---------------------------------------------------------------
# BILLING EMAIL 3: LegalCosts — Budget update
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From accounting@legalcosts.com Fri Feb 21 10:00:00 2025
From: Accounting Department <accounting@legalcosts.com>
To: paralegal@whitmorelaw.com
Subject: Re: Q4 Budget
Date: Fri, 21 Feb 2025 10:00:00 -0500
Message-ID: <lit-billing-003@legalcosts.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Whitmore & Associates,

Per your request, here is the budget variance analysis for the Meridian Corp v. Apex Industries litigation through Q4 2024:

Approved Annual Budget:        $250,000.00
Spent Year-to-Date:            $183,475.00
Remaining Budget:               $66,525.00
Utilization Rate:                     73.4%

At the current burn rate, the approved budget will be exhausted by approximately mid-April 2025. We recommend requesting a budget increase of $75,000 from the client to cover anticipated trial preparation costs.

The largest upcoming expenditure is the expert witness trial testimony fee (estimated $35,000) and trial exhibit preparation ($15,000-$20,000).

Accounting Department
LegalCosts Solutions

MBOX_MSG

# ---------------------------------------------------------------
# NON-CASE EMAIL 1: HR — Firm announcement (stays in Inbox)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From hr@whitmorelaw.com Mon Feb 24 09:00:00 2025
From: Human Resources <hr@whitmorelaw.com>
To: all-staff@whitmorelaw.com
Subject: Firm-Wide Announcement
Date: Mon, 24 Feb 2025 09:00:00 -0500
Message-ID: <noncase-001@whitmorelaw.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Colleagues,

Please mark your calendars for the following upcoming events:

1. Annual Partner Reception — Friday, March 14 at 6:00 PM (Rooftop Terrace)
2. New dental and vision benefits enrollment opens March 1 through March 31
3. The office will be closed on Monday, February 17 for Presidents' Day

Additionally, we are pleased to announce that Associate Sarah Kim has been selected for the State Bar Leadership Academy. Congratulations, Sarah!

Best regards,
Human Resources Department
Whitmore & Associates

MBOX_MSG

# ---------------------------------------------------------------
# NON-CASE EMAIL 2: IT — System maintenance (stays in Inbox)
# ---------------------------------------------------------------
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From it@whitmorelaw.com Tue Feb 25 16:00:00 2025
From: IT Department <it@whitmorelaw.com>
To: all-staff@whitmorelaw.com
Subject: System Maintenance Notice
Date: Tue, 25 Feb 2025 16:00:00 -0500
Message-ID: <noncase-002@whitmorelaw.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

All Staff,

Scheduled maintenance will be performed on the firm's email server and document management system this Saturday, March 1, from 2:00 AM to 6:00 AM EST.

During this window, you may experience brief interruptions to email access and the iManage document system. All data will be preserved. No action is required on your part.

If you have urgent matters requiring system access during this time, please contact the IT Help Desk at ext. 4500 before Friday COB.

IT Department
Whitmore & Associates

MBOX_MSG

chown -R ga:ga "$INBOX_MBOX"
echo "Injected 15 litigation emails into Inbox (5 Pleadings + 5 Discovery + 3 Billing + 2 Non-case)"

# ============================================================
# STEP 4: Remove Inbox.msf so Thunderbird rebuilds the index
# ============================================================
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf"
rm -f "${LOCAL_MAIL_DIR}/"*.msf
echo "Removed .msf index files"

# ============================================================
# STEP 5: Clean filter rules (fresh start)
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
# STEP 6: Remove Rebecca Torres from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        # Remove by email
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%r.torres%'")
        cards = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%torres%kline%'")
        cards += [r[0] for r in cur.fetchall()]
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 'r.torres@kline-harris.com'")
        cards += [r[0] for r in cur.fetchall()]
        cards = list(set(cards))
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Rebecca Torres entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 7: Remove any existing drafts to Torres
# ============================================================
DRAFTS_MBOX="${LOCAL_MAIL_DIR}/Drafts"
if [ -f "$DRAFTS_MBOX" ]; then
    python3 << 'PYEOF'
import mailbox, os, shutil

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")
if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        keys_to_remove = []
        for key, msg in mb.items():
            to_header = (msg.get('To', '') + ' ' + msg.get('to', '')).lower()
            if 'torres' in to_header or 'kline-harris' in to_header:
                keys_to_remove.append(key)
        for key in reversed(keys_to_remove):
            mb.remove(key)
        mb.flush()
        mb.close()
        print(f"Removed {len(keys_to_remove)} drafts to Torres")
    except Exception as e:
        print(f"Draft cleanup: {e}")
PYEOF
    rm -f "${DRAFTS_MBOX}.msf"
fi

# ============================================================
# STEP 8: Record baseline state AFTER all cleanup (anti-gaming)
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/litigation_email_triage_inbox_baseline
date +%s > /tmp/litigation_email_triage_start_ts
echo "Baseline inbox count: $INBOX_COUNT"
echo "Task start timestamp recorded"

# ============================================================
# STEP 9: Launch Thunderbird and wait for it to be ready
# ============================================================
start_thunderbird
wait_for_thunderbird_window 45
sleep 5
maximize_thunderbird
sleep 2

take_screenshot /tmp/litigation_email_triage_start_screenshot.png
echo "Start screenshot saved"

echo "=== litigation_email_triage setup complete ==="
echo "Inbox contains 15 emails from Meridian v. Apex litigation"
echo "Agent must read email bodies to classify — senders overlap across categories"
