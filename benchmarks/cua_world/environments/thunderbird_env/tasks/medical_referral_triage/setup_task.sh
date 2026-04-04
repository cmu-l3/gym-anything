#!/bin/bash
# Setup script for medical_referral_triage task
# Practice Manager at Oakwood Medical Group — patient referral inbox organization

echo "=== Setting up medical_referral_triage task ==="

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
rm -f /tmp/medical_referral_triage_result.json 2>/dev/null || true
rm -f /tmp/medical_referral_triage_start_ts 2>/dev/null || true
rm -f /tmp/medical_referral_triage_inbox_baseline 2>/dev/null || true
rm -f /tmp/medical_referral_triage_abook_check.json 2>/dev/null || true

# Remove pre-existing referral folders (clean slate)
rm -f "${LOCAL_MAIL_DIR}/Referrals" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Referrals.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Referrals.sbd" 2>/dev/null || true

# ============================================================
# STEP 3: Inject 9 professional medical referral emails into Inbox
# 3 urgent referrals + 4 routine referrals + 2 admin/non-referral
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# --- Urgent Referrals (3 emails with [URGENT] in subject) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From p.nguyen@bayviewcardiology.com Mon Mar 10 07:45:00 2025
From: Dr. Patricia Nguyen <p.nguyen@bayviewcardiology.com>
To: referrals@oakwoodmedical.com
Subject: [URGENT] Cardiac Referral - James Morrison, DOB 1952-03-14 - Unstable Angina
Date: Mon, 10 Mar 2025 07:45:00 -0800
Message-ID: <urgent-001@bayviewcardiology.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

To the Referral Coordinator at Oakwood Medical Group,

I am urgently referring my patient James Morrison (DOB: March 14, 1952, MRN: BVC-20847) for cardiology follow-up. Mr. Morrison presented to our urgent care yesterday with new-onset chest pain at rest with characteristic features of unstable angina. He was stabilized, troponin was mildly elevated at 0.08, and he was discharged on dual antiplatelet therapy.

He requires stress testing (nuclear preferred) within 48-72 hours and a cardiologist consultation no later than Thursday. If earlier availability exists, please prioritize.

Insurance: BlueCross BlueShield HMO, ID BC-9871234

Please call me directly at (415) 555-0172 if there are any scheduling complications.

Dr. Patricia Nguyen, MD, FACC
Bayview Cardiology Specialists
p.nguyen@bayviewcardiology.com

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dr.patel@emergentneurology.com Mon Mar 10 11:20:00 2025
From: Dr. Rajan Patel <dr.patel@emergentneurology.com>
To: referrals@oakwoodmedical.com
Subject: [URGENT] Post-TIA Neurology Follow-up - Elena Vasquez, DOB 1961-07-22
Date: Mon, 10 Mar 2025 11:20:00 -0800
Message-ID: <urgent-002@emergentneurology.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

I am sending an urgent referral for Elena Vasquez (DOB: July 22, 1961, MRN: EN-5531) who was seen in our neurology department following a transient ischemic attack on March 8th. MRI diffusion-weighted imaging showed no acute infarction, and she was discharged on clopidogrel and a statin.

Per current TIA guidelines, she requires:
1. Carotid duplex ultrasound within 24-48 hours
2. Echocardiogram within 72 hours
3. Neurology follow-up appointment within one week

Please treat this as a high-priority scheduling request. Her coverage is Aetna PPO, Group #AET-4422.

Dr. Rajan Patel, MD
Emergent Neurology Associates
dr.patel@emergentneurology.com

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dr.rodriguez@coastalorthopedics.com Tue Mar 11 09:00:00 2025
From: Dr. Maria Rodriguez <dr.rodriguez@coastalorthopedics.com>
To: referrals@oakwoodmedical.com
Subject: [URGENT] Post-Surgical Wound Concern - Robert Kim, DOB 1978-11-05
Date: Tue, 11 Mar 2025 09:00:00 -0800
Message-ID: <urgent-003@coastalorthopedics.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

I am referring Robert Kim (DOB: November 5, 1978, MRN: CO-7734) for urgent wound care evaluation. Mr. Kim is 12 days post right knee arthroscopy and presented to our office today with signs of superficial wound dehiscence and early cellulitis. We have started him on oral antibiotics but want infectious disease or wound care specialist evaluation within 48 hours.

Temperature was 38.1°C at today's visit. WBC was 12.4 on this morning's labs.

Please schedule with wound care or ID at your earliest availability.

Insurance: United Healthcare Choice Plus, Member ID: UH-334891

Dr. Maria Rodriguez, MD
Coastal Orthopedics
dr.rodriguez@coastalorthopedics.com

MBOX_MSG

# --- Routine Referrals (4 emails — standard, no [URGENT]) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From p.nguyen@bayviewcardiology.com Mon Mar 10 14:30:00 2025
From: Dr. Patricia Nguyen <p.nguyen@bayviewcardiology.com>
To: referrals@oakwoodmedical.com
Subject: Routine Cardiology Referral - Annual Follow-up - Margaret Walsh, DOB 1945-09-12
Date: Mon, 10 Mar 2025 14:30:00 -0800
Message-ID: <routine-001@bayviewcardiology.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

I am referring Margaret Walsh (DOB: September 12, 1945, MRN: BVC-19203) for routine annual cardiology follow-up. Ms. Walsh has a history of stable coronary artery disease, well-managed on medical therapy. Her last echo was two years ago and we would like a repeat assessment at her convenience.

This is a non-urgent referral. Appointment within the next 4-6 weeks is appropriate.

Insurance: Medicare Supplement Plan G

Dr. Patricia Nguyen, MD, FACC
Bayview Cardiology Specialists

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dr.stevens@pacificorthopedics.com Tue Mar 11 10:00:00 2025
From: Dr. Alan Stevens <dr.stevens@pacificorthopedics.com>
To: referrals@oakwoodmedical.com
Subject: Orthopedic Referral - Hip Assessment - Frank Torres, DOB 1950-04-28
Date: Tue, 11 Mar 2025 10:00:00 -0800
Message-ID: <routine-002@pacificorthopedics.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

Please schedule Frank Torres (DOB: April 28, 1950, MRN: PO-44821) for orthopedic consultation regarding progressive right hip pain. X-rays demonstrate moderate joint space narrowing consistent with osteoarthritis. Conservative management has been attempted for 6 months without adequate relief.

Standard referral timeframe is acceptable — within the next 3-4 weeks.

Insurance: Cigna PPO, ID: CIG-7734521

Dr. Alan Stevens, MD
Pacific Orthopedics & Sports Medicine

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dr.kim@dermatologywest.com Tue Mar 11 13:45:00 2025
From: Dr. Susan Kim <dr.kim@dermatologywest.com>
To: referrals@oakwoodmedical.com
Subject: Dermatology Referral - Skin Cancer Screening - Thomas Park, DOB 1963-12-17
Date: Tue, 11 Mar 2025 13:45:00 -0800
Message-ID: <routine-003@dermatologywest.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

I am referring Thomas Park (DOB: December 17, 1963, MRN: DW-8820) for comprehensive skin cancer screening. He has a family history of melanoma (father, paternal aunt) and has not had a full-body skin exam in 4 years. Several atypical-appearing lesions were noted on the back during his recent physical.

Routine scheduling is appropriate. Within 6-8 weeks is acceptable.

Insurance: Aetna PPO, Group #AET-6612

Dr. Susan Kim, MD, FAAD
Dermatology West

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From dr.williams@bayareaphysicaltherapy.com Wed Mar 12 08:30:00 2025
From: Dr. Lisa Williams <dr.williams@bayareaphysicaltherapy.com>
To: referrals@oakwoodmedical.com
Subject: PT Referral - Post-Surgical Rehabilitation - David Park, DOB 1984-06-03
Date: Wed, 12 Mar 2025 08:30:00 -0800
Message-ID: <routine-004@bayareaphysicaltherapy.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Referral Coordinator,

Please schedule David Park (DOB: June 3, 1984, MRN: BAPT-3301) for post-surgical physical therapy following right rotator cuff repair performed March 4, 2025. Recommend 2-3 sessions per week for 12 weeks per the surgeon's protocol.

Routine scheduling — he can begin as early as next week.

Insurance: Kaiser Permanente HMO

Dr. Lisa Williams, DPT
Bay Area Physical Therapy Associates

MBOX_MSG

# --- Admin/non-referral emails (2 — should remain in Inbox) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From billing@oakwoodmedical.com Mon Mar 10 09:00:00 2025
From: Billing Department <billing@oakwoodmedical.com>
To: referrals@oakwoodmedical.com
Subject: March 2025 Insurance Verification Batch - Action Required
Date: Mon, 10 Mar 2025 09:00:00 -0800
Message-ID: <admin-001@oakwoodmedical.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Practice Manager,

Please review the attached insurance verification batch for this week's appointments. Seven patients have coverage discrepancies that require manual verification before their scheduled dates. The list has been uploaded to the billing portal.

Billing Department
Oakwood Medical Group

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From hr@oakwoodmedical.com Wed Mar 12 10:00:00 2025
From: Human Resources <hr@oakwoodmedical.com>
To: referrals@oakwoodmedical.com
Subject: Staff Schedule Update - Week of March 17 - Front Desk Coverage
Date: Wed, 12 Mar 2025 10:00:00 -0800
Message-ID: <admin-002@oakwoodmedical.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Practice Manager,

As discussed, Sarah Chen will be on PTO March 17-19. Coverage for the front desk has been arranged with Angela from the Walnut Creek office. Please coordinate the referral inbox handoff with her by end of week.

Human Resources
Oakwood Medical Group

MBOX_MSG

chown -R ga:ga "$INBOX_MBOX"
echo "Injected 9 medical referral emails into Inbox"

# ============================================================
# STEP 4: Clean filter rules
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
# STEP 5: Remove Dr. Patricia Nguyen from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%p.nguyen%bayview%'")
        cards = [r[0] for r in cur.fetchall()]
        # Also check by name
        cur.execute("SELECT card FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%nguyen%'")
        cards += [r[0] for r in cur.fetchall()]
        cards = list(set(cards))
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Dr. Nguyen entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 6: Record baseline AFTER all cleanup
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/medical_referral_triage_inbox_baseline
date +%s > /tmp/medical_referral_triage_start_ts
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

take_screenshot /tmp/medical_referral_triage_start_screenshot.png
echo "Start screenshot saved"

echo "=== medical_referral_triage setup complete ==="
echo "Inbox contains 9 emails: 3 urgent [URGENT] + 4 routine + 2 admin"
