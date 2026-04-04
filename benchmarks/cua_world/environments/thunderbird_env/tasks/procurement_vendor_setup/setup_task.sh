#!/bin/bash
# Setup script for procurement_vendor_setup task
# Procurement Director at Summit Manufacturing — vendor inbox organization

echo "=== Setting up procurement_vendor_setup task ==="

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
rm -f /tmp/procurement_vendor_setup_result.json 2>/dev/null || true
rm -f /tmp/procurement_vendor_setup_start_ts 2>/dev/null || true
rm -f /tmp/procurement_vendor_setup_inbox_baseline 2>/dev/null || true
rm -f /tmp/procurement_vendor_setup_abook_check.json 2>/dev/null || true

# Remove pre-existing vendor folders
rm -f "${LOCAL_MAIL_DIR}/Vendors" 2>/dev/null || true
rm -f "${LOCAL_MAIL_DIR}/Vendors.msf" 2>/dev/null || true
rm -rf "${LOCAL_MAIL_DIR}/Vendors.sbd" 2>/dev/null || true

# ============================================================
# STEP 3: Inject 9 purchasing emails into Inbox
# 4 RFQ responses + 3 contract review + 2 logistics/admin
# ============================================================
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
> "$INBOX_MBOX"
echo "Cleared inbox for fresh task setup"

# --- Active RFQ emails (4 — quotation and bid correspondence) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From s.chen@globalsupplyco.com Mon Mar 10 09:30:00 2025
From: Sandra Chen <s.chen@globalsupplyco.com>
To: procurement@summitmfg.com
Subject: RFQ Response #RFQ-2025-0187 - Stainless Steel 316L Tubing - 500 Unit Quote
Date: Mon, 10 Mar 2025 09:30:00 -0800
Message-ID: <rfq-001@globalsupplyco.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Procurement Team at Summit Manufacturing,

Thank you for submitting RFQ #2025-0187. Please find our formal quotation below:

Product: Stainless Steel 316L Seamless Tubing, 2" OD x 0.065" wall
Quantity: 500 units (20-foot sections)
Unit Price: $48.75
Total: $24,375.00
Lead Time: 4-6 weeks from PO receipt
FOB: Our warehouse, Chicago IL
Payment Terms: Net-30

This quote is valid for 30 days. We can also offer a 3% volume discount if quantity is increased to 750+ units.

Please let me know if you'd like to schedule a call to discuss specifications or delivery requirements.

Best regards,
Sandra Chen
Senior Account Manager
Global Supply Co
s.chen@globalsupplyco.com | (312) 555-0247

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From bids@industrialparts.com Mon Mar 10 14:15:00 2025
From: Bid Response Team <bids@industrialparts.com>
To: procurement@summitmfg.com
Subject: Quotation Submission - Carbon Steel Plate Q2 2025 - Bid #IP-447
Date: Mon, 10 Mar 2025 14:15:00 -0800
Message-ID: <rfq-002@industrialparts.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Summit Manufacturing Procurement,

We are pleased to submit our quotation for your Q2 2025 raw materials RFQ:

Item: A36 Carbon Steel Plate, 0.25" thickness, 4'x8' sheets
Quantity Requested: 200 sheets
Our Bid Price: $62.40 per sheet (FOB our facility, Joliet IL)
Total Bid Value: $12,480.00
Delivery: 3-4 weeks from order confirmation
Min. Order: 50 sheets

We have 150 sheets available from current inventory (available for immediate shipment) and can source remaining quantities within our stated lead time.

Bid valid 45 days. We welcome a competitive comparison with other suppliers.

Industrial Parts & Metals, Inc.
Bid #IP-447

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From s.chen@globalsupplyco.com Tue Mar 11 11:00:00 2025
From: Sandra Chen <s.chen@globalsupplyco.com>
To: procurement@summitmfg.com
Subject: Revised Pricing - RFQ-2025-0187 - Volume Discount Applied
Date: Tue, 11 Mar 2025 11:00:00 -0800
Message-ID: <rfq-003@globalsupplyco.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi Procurement Team,

Following our call this morning, I am pleased to revise our quotation for RFQ #2025-0187 to reflect the volume adjustment you mentioned:

Revised Quantity: 750 units (as discussed)
Original Unit Price: $48.75
Volume Discount (3%): -$1.46
Revised Unit Price: $47.29
Revised Total: $35,467.50

All other terms remain as quoted on March 10. I've also confirmed with our warehouse that we can accommodate your requested delivery window of May 5-9.

Please let me know when you're ready to issue the PO so we can reserve inventory.

Sandra Chen
Global Supply Co

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From procurement@alloymaster.com Wed Mar 12 10:30:00 2025
From: Sales Team <procurement@alloymaster.com>
To: procurement@summitmfg.com
Subject: Alloy Components Quotation - Summit Manufacturing RFQ - Inconel 625 Parts
Date: Wed, 12 Mar 2025 10:30:00 -0800
Message-ID: <rfq-004@alloymaster.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Attn: Summit Manufacturing Procurement Director,

Alloy Master Components is pleased to respond to your request for Inconel 625 precision machined parts:

Part Numbers Quoted: SM-7741-A, SM-7742-B, SM-7743-C (per your drawings Rev C dated Feb 2025)
Quantities: 25 each
Unit Pricing: SM-7741-A: $218.00 | SM-7742-B: $195.50 | SM-7743-C: $312.00
Total Quotation Value: $18,137.50
Lead Time: 8-10 weeks (includes machining and inspection)
Certifications: All parts supplied with material certs (EN 10204 3.1) and CMM inspection reports

Note: Inconel 625 raw material pricing is subject to market fluctuation. This quote is locked for 21 days only.

Alloy Master Components, Inc.
sales@alloymaster.com | (847) 555-0194

MBOX_MSG

# --- Contract Review emails (3 — agreements requiring legal review) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From legal@globalsupplyco.com Tue Mar 11 08:45:00 2025
From: Legal Department <legal@globalsupplyco.com>
To: procurement@summitmfg.com
Subject: Master Supply Agreement FY2025 - Signature Required - Global Supply Co
Date: Tue, 11 Mar 2025 08:45:00 -0800
Message-ID: <contract-001@globalsupplyco.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Dear Summit Manufacturing,

Attached is the executed Master Supply Agreement for fiscal year 2025. This agreement supersedes the 2024 MSA and incorporates the following amendments negotiated last quarter:

1. Extended payment terms from Net-30 to Net-45 (Section 6.1)
2. Updated force majeure clause covering supply chain disruptions (Section 12.3)
3. New pricing adjustment mechanism tied to LME metals index (Exhibit B)
4. Increased annual volume commitment from $800K to $1.2M

Please have your authorized signatory execute the agreement and return one original by March 21, 2025. The agreement becomes effective April 1, 2025.

Questions? Contact our legal team at legal@globalsupplyco.com.

Global Supply Co Legal Department

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From contracts@industrialparts.com Wed Mar 12 14:00:00 2025
From: Contract Administration <contracts@industrialparts.com>
To: procurement@summitmfg.com
Subject: Amendment to Purchase Order #PO-2024-8831 - Payment Terms Change Net-30 to Net-45
Date: Wed, 12 Mar 2025 14:00:00 -0800
Message-ID: <contract-002@industrialparts.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Summit Manufacturing Procurement,

This letter confirms the agreed amendment to Purchase Order #PO-2024-8831 (issued December 14, 2024) for A36 steel plate. As mutually agreed, payment terms are amended from Net-30 to Net-45, effective for all invoices dated after March 1, 2025.

Please execute the attached amendment and return via email. Our accounts receivable department requires the executed copy before processing your March invoices.

If there are any discrepancies with your records, please contact us immediately.

Contract Administration
Industrial Parts & Metals, Inc.

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From s.chen@globalsupplyco.com Thu Mar 13 09:00:00 2025
From: Sandra Chen <s.chen@globalsupplyco.com>
To: procurement@summitmfg.com
Subject: Contract Addendum - Force Majeure Clause - Tariff Escalation Provision
Date: Thu, 13 Mar 2025 09:00:00 -0800
Message-ID: <contract-003@globalsupplyco.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi,

Following the trade policy changes announced last week, our legal team has drafted a contract addendum to address potential tariff escalation scenarios that fall outside the existing force majeure clause in our FY2025 MSA.

The addendum adds Section 12.4: If steel or alloy import tariffs increase by more than 15% from baseline within any 90-day period, either party may request a pricing review within 30 days. This protects both parties from unilateral margin pressure.

I'm attaching the addendum for your review. Our legal team needs your response by March 19. No changes to existing terms or commitments.

Sandra Chen
Global Supply Co

MBOX_MSG

# --- Admin/logistics emails (2 — should stay in Inbox) ---
cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From warehouse@summitmfg.com Mon Mar 10 16:00:00 2025
From: Warehouse Operations <warehouse@summitmfg.com>
To: procurement@summitmfg.com
Subject: March Physical Inventory Count - Procurement Input Needed
Date: Mon, 10 Mar 2025 16:00:00 -0800
Message-ID: <admin-001@summitmfg.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Procurement Director,

The March physical inventory count is scheduled for March 22-23. We'll need you to provide an updated open PO report so we can reconcile against expected receipts. Please send the open PO list by March 19 COB.

Also flagging: Bay 7 is at 94% capacity. Incoming material for PO-2025-0034 (arriving March 20) may require temporary offsite storage. Please advise.

Warehouse Operations
Summit Manufacturing

MBOX_MSG

cat >> "$INBOX_MBOX" << 'MBOX_MSG'
From shipping@fastfreight.com Wed Mar 12 11:00:00 2025
From: FastFreight Logistics <shipping@fastfreight.com>
To: procurement@summitmfg.com
Subject: Shipment Update - Pro# FF-2025-3392 - Expected Delivery March 18
Date: Wed, 12 Mar 2025 11:00:00 -0800
Message-ID: <logistics-001@fastfreight.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Summit Manufacturing,

This is an automated shipment status notification for Pro# FF-2025-3392 (Summit Manufacturing, Receiver).

Current Status: In Transit — Chicago Hub
Origin: Cleveland, OH
Destination: Summit Manufacturing, Rockford, IL
Estimated Delivery: March 18, 2025 (1:00 PM - 5:00 PM window)
Weight: 1,847 lbs | Pieces: 12 pallets

For questions, contact our dispatch at (800) 555-3300 or reference Pro# FF-2025-3392.

FastFreight Logistics

MBOX_MSG

chown -R ga:ga "$INBOX_MBOX"
echo "Injected 9 procurement/vendor emails into Inbox"

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
# STEP 5: Remove Sandra Chen from address book if exists
# ============================================================
python3 << 'PYEOF'
import sqlite3, os

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%s.chen%globalsupply%'")
        cards = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 's.chen@globalsupplyco.com'")
        cards += [r[0] for r in cur.fetchall()]
        cards = list(set(cards))
        for card_id in cards:
            cur.execute("DELETE FROM properties WHERE card=?", (card_id,))
        conn.commit()
        conn.close()
        print(f"Removed {len(cards)} existing Sandra Chen entries from address book")
    except Exception as e:
        print(f"Address book cleanup: {e}")
else:
    print("Address book not found — will be created fresh by Thunderbird")
PYEOF

# ============================================================
# STEP 6: Record baseline
# ============================================================
INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")
echo "$INBOX_COUNT" > /tmp/procurement_vendor_setup_inbox_baseline
date +%s > /tmp/procurement_vendor_setup_start_ts
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

take_screenshot /tmp/procurement_vendor_setup_start_screenshot.png
echo "Start screenshot saved"

echo "=== procurement_vendor_setup setup complete ==="
echo "Inbox contains 9 emails: 4 RFQ responses + 3 contract documents + 2 admin/logistics"
