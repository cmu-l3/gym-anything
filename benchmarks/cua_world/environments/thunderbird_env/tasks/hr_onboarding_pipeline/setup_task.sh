#!/bin/bash
# Setup script for hr_onboarding_pipeline task
# HR Manager at TechVenture Corp — new employee onboarding inbox organization

echo "=== Setting up hr_onboarding_pipeline task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# STEP 1: Close Thunderbird
# ============================================================
close_thunderbird
sleep 3
echo "Thunderbird closed for setup"

# ============================================================
# STEP 2: Remove stale task files
# ============================================================
rm -f /tmp/hr_onboarding_pipeline_result.json 2>/dev/null || true
rm -f /tmp/hr_onboarding_pipeline_start_ts 2>/dev/null || true
rm -f /tmp/hr_onboarding_pipeline_inbox_baseline 2>/dev/null || true
rm -f /tmp/hr_onboarding_pipeline_abook_check.json 2>/dev/null || true

# Remove pre-existing onboarding folders
rm -f "${LOCAL_MAIL_DIR}/Onboarding_Q1" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Onboarding_Q1.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Onboarding_Q1.sbd" 2>/dev/null || true

# ============================================================
# STEP 3: Inject 9 emails into Inbox
# 3 documents-pending + 4 IT requests + 2 general HR
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# --- Documents Pending emails (3 — new hires missing paperwork) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From alex.johnson@gmail.com Mon Mar 10 09:00:00 2025
From: Alex Johnson <alex.johnson@gmail.com>
To: hr@techventure.com
Subject: Onboarding Documents - Alex Johnson - Software Engineer (Start Date March 17)
Date: Mon, 10 Mar 2025 09:00:00 -0800
Message-ID: <docs-001@gmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi HR Team,

I'm Alex Johnson, starting as a Software Engineer on March 17th. I've submitted my direct deposit form and tax withholding, but I realized I still need to complete:

1. I-9 employment eligibility verification (need to bring originals on my first day)
2. Non-disclosure agreement (waiting for the DocuSign link)
3. Stock option election form (received it but wasn't sure if I needed to complete it before Day 1)

Could someone let me know what I still owe and confirm what I need to bring on Monday?

Thanks,
Alex Johnson

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From sarah.kim.newhire@protonmail.com Mon Mar 10 13:30:00 2025
From: Sarah Kim <sarah.kim.newhire@protonmail.com>
To: hr@techventure.com
Subject: Missing Onboarding Forms - Sarah Kim - Product Manager
Date: Mon, 10 Mar 2025 13:30:00 -0800
Message-ID: <docs-002@protonmail.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hello,

I'm Sarah Kim, joining as Product Manager on March 17th. My recruiter mentioned there were a few outstanding documents in my onboarding checklist. I completed everything I received via email, but I haven't received the background check authorization form or the handbook acknowledgment.

Can you resend those two documents? Also, my emergency contact form was mailed to my old address — do you need an updated one?

Sarah Kim
Incoming PM, TechVenture Corp

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From recruiter@talentbridge.com Tue Mar 11 10:00:00 2025
From: Christine Park <recruiter@talentbridge.com>
To: hr@techventure.com
Subject: New Placement - Robert Chen - Senior DevOps Engineer - Documents Required
Date: Tue, 11 Mar 2025 10:00:00 -0800
Message-ID: <docs-003@talentbridge.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi HR Team,

I'm following up on the placement of Robert Chen (Senior DevOps Engineer, start date March 17). Per your onboarding requirements, Robert still needs to submit:

- Signed offer letter (he has a question about the relocation addendum)
- Benefits enrollment form (deadline: March 14)
- Signed arbitration agreement

I've CC'd Robert on a separate email with the DocuSign links. Please let me know if his file is otherwise complete.

Christine Park
Senior Technical Recruiter
TalentBridge Staffing

MBOX_MSG

# --- IT Request emails (4 — from IT department @techventure-it.com) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From m.thompson@techventure-it.com Mon Mar 10 08:00:00 2025
From: Marcus Thompson <m.thompson@techventure-it.com>
To: hr@techventure.com
Subject: IT Setup Request - New Employee: Alex Johnson - Equipment Assignment
Date: Mon, 10 Mar 2025 08:00:00 -0800
Message-ID: <it-001@techventure-it.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

I've received the new hire notification for Alex Johnson (Software Engineer, starting March 17). Please confirm the following IT provisioning plan:

- MacBook Pro 16" M4 Pro — pulling from inventory (SN: TVR-MBP-2441)
- External monitor (27") — reserved from March 14 equipment room
- RSA software token — enrollment pending employee email address
- GitHub Enterprise access — need manager approval from Engineering Director first

Please send me Alex's preferred email format once his account is created in Workday. I'll have his workstation ready by Friday EOD.

Marcus Thompson
IT Director | TechVenture Corp
m.thompson@techventure-it.com | ext. 2200

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From m.thompson@techventure-it.com Mon Mar 10 15:45:00 2025
From: Marcus Thompson <m.thompson@techventure-it.com>
To: hr@techventure.com
Subject: IT Setup - Sarah Kim (PM) - MacBook + Security Badge + Slack Provisioning
Date: Mon, 10 Mar 2025 15:45:00 -0800
Message-ID: <it-002@techventure-it.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

For Sarah Kim starting March 17 as Product Manager:

Hardware:
- MacBook Pro 14" M4 — shipping from Apple (arriving Thursday, tracking TVR-2025-334)
- USB-C hub + peripherals — already on her desk in B202

Access provisioning (waiting on HR confirmation of start date and title):
- Jira/Confluence — PM tier license
- Figma — professional seat
- Looker — view-only access initially; manager can escalate
- Physical badge — please send employee ID number once issued

Badge issue: the badge printer in the main office is down. Backup is at the Sunnyvale annex. Can you confirm which office Sarah will badge into first?

Marcus Thompson
IT Director | TechVenture Corp

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From helpdesk@techventure-it.com Tue Mar 11 09:30:00 2025
From: IT Help Desk <helpdesk@techventure-it.com>
To: hr@techventure.com
Subject: New Employee Account Creation - Robert Chen - Active Directory + VPN
Date: Tue, 11 Mar 2025 09:30:00 -0800
Message-ID: <it-003@techventure-it.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

This is a notification that we have initiated account creation for Robert Chen (Senior DevOps Engineer) per the onboarding request submitted by Marcus Thompson. Status:

- Active Directory account: CREATED (rchen@techventure.com, temp password sent via secure link)
- VPN certificate: PENDING — requires signed security acknowledgment from HR file
- AWS IAM (DevOps group): PENDING — requires clearance from CISO for production access
- 1Password team seat: PROVISIONED

Action needed from HR: please send us the signed security acknowledgment form from Robert's file before Thursday March 13 so we can complete VPN enrollment before his start date.

IT Help Desk
TechVenture Corp

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From m.thompson@techventure-it.com Wed Mar 12 14:00:00 2025
From: Marcus Thompson <m.thompson@techventure-it.com>
To: hr@techventure.com
Subject: Q1 2025 New Hire Batch - VPN Access and Security Training Links
Date: Wed, 12 Mar 2025 14:00:00 -0800
Message-ID: <it-004@techventure-it.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

For all Q1 2025 new hires (Johnson, Kim, Chen), please distribute the following before their first day:

1. Security awareness training link: https://training.techventure-it.com/new-hire-2025 (required before VPN activation)
2. VPN client download instructions (attached PDF — distribute via onboarding portal)
3. IT onboarding checklist (attached — one per new hire, to be completed Day 1)

Note: VPN cannot be activated until security training is confirmed complete in our system. This typically takes 24 hours after course completion. Please advise new hires accordingly so they can complete training during their first week.

If any new hire needs a hardware exception (e.g., existing personal laptop for remote use), route that request directly to me.

Marcus Thompson
IT Director | TechVenture Corp

MBOX_MSG

# --- General HR/admin emails (2 — should remain in Inbox) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From payroll@techventure.com Tue Mar 11 11:00:00 2025
From: Payroll Department <payroll@techventure.com>
To: hr@techventure.com
Subject: Q1 2025 Payroll Processing Cutoff - March 14 Deadline
Date: Tue, 11 Mar 2025 11:00:00 -0800
Message-ID: <payroll-001@techventure.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

Reminder that the payroll cutoff for Q1 new hires is March 14 at 5:00 PM PT. Any employees not fully processed by this deadline will receive their first paycheck on April 4 instead of March 28.

Please ensure all new hire records are entered in Workday with banking information confirmed before the cutoff.

Payroll Department
TechVenture Corp

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From benefits@techventure.com Wed Mar 12 09:00:00 2025
From: Benefits Administration <benefits@techventure.com>
To: hr@techventure.com
Subject: Open Enrollment Reminder - New Hire Benefits Window Closing March 17
Date: Wed, 12 Mar 2025 09:00:00 -0800
Message-ID: <benefits-001@techventure.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

HR Team,

This is a reminder that the benefits enrollment window for Q1 new hires closes on March 17 (their first day). Employees who do not complete enrollment will be defaulted to the base medical plan with no dental/vision.

Please ensure all three new hires (Johnson, Kim, Chen) are aware of the deadline and have access to the benefits portal.

Benefits Administration
TechVenture Corp

MBOX_MSG

chown -R ga:ga "$INBOX_MBOX"
echo "Injected 9 HR onboarding emails into Inbox"

# ============================================================
# STEP 4: Remove any pre-existing draft to Marcus Thompson
# ============================================================
python3 << 'PYEOF'
import mailbox, os

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")
if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        mb.lock()
        to_remove = []
        for key, msg in mb.items():
            to_header = (msg.get('To', '') or '').lower()
            if 'm.thompson' in to_header or 'techventure-it.com' in to_header:
                to_remove.append(key)
        for key in to_remove:
            mb.remove(key)
        mb.flush()
        mb.unlock()
        mb.close()
        print(f"Removed {len(to_remove)} pre-existing draft(s) to Marcus Thompson")
    except Exception as e:
        print(f"Draft cleanup: {e}")
else:
    print("Drafts mbox not found — nothing to clean")
PYEOF

# ============================================================
# STEP 5: Remove Marcus Thompson from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%m.thompson%techventure%'")
        cards = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT card FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%thompson%'")
        cards += [r[0] for r in cur.fetchall()]
        cards = list(set(cards))
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Marcus Thompson entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 6: Record baseline
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/hr_onboarding_pipeline_inbox_baseline
date +%s > /tmp/hr_onboarding_pipeline_start_ts
echo "Baseline inbox count: $INBOX_COUNT"
echo "Task start timestamp recorded"

# ============================================================
# STEP 7: Launch Thunderbird
# ============================================================
start_thunderbird
wait_for_thunderbird_window 45
sleep 5
maximize_thunderbird
sleep 2

take_screenshot /tmp/hr_onboarding_pipeline_start_screenshot.png
echo "Start screenshot saved"

echo "=== hr_onboarding_pipeline setup complete ==="
echo "Inbox contains 9 emails: 3 documents-pending + 4 IT requests + 2 general HR"
