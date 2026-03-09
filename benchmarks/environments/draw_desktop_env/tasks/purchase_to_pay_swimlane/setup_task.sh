#!/bin/bash
# Do NOT use set -e

echo "=== Setting up purchase_to_pay_swimlane task ==="

DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

rm -f /home/ga/Desktop/p2p_process.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/p2p_process.pdf 2>/dev/null || true

# Create the P2P process specification document.
# Based on the APQC Process Classification Framework (PCF) and SAP Best Practices
# for Source-to-Pay (https://www.apqc.org/process-frameworks) — public domain process standard.
cat > /home/ga/Desktop/p2p_process_spec.txt << 'SPECEOF'
Purchase-to-Pay (P2P) Process Specification
============================================
Organization: Meridian Manufacturing Inc.
Standard: APQC Process Classification Framework v7.3
Process Owner: VP of Finance & Operations
Scope: Indirect and direct material procurement

SWIM LANE DEPARTMENTS (5 Lanes Required)
-----------------------------------------
1. REQUESTER        (internal employee who initiates the need)
2. PROCUREMENT      (sourcing & purchasing team)
3. ACCOUNTS PAYABLE (AP team — invoice processing & payment)
4. SUPPLIER         (external vendor)
5. FINANCE/TREASURY (budget control & payment authorization)

PROCESS STEPS (place in correct department lane)
------------------------------------------------

[START EVENT] — Requester identifies a need

STEP 1  [Requester]       Create Purchase Requisition (PR)
        Document: Purchase Requisition form
        → Submit for budget approval

STEP 2  [Finance/Treasury] Budget Approval
        DECISION GATEWAY: "Budget Available?"
        → YES: Approve PR → forward to Procurement
        → NO: Reject PR → notify Requester (LOOP BACK to Step 1 or END)

STEP 3  [Procurement]     Evaluate and Select Supplier
        If approved supplier exists: use approved vendor list
        If new supplier needed:
          DECISION GATEWAY: "New Vendor Required?"
          → YES: Vendor onboarding subprocess (parallel branch)
          → NO: Continue to Step 4

STEP 4  [Procurement]     Issue Purchase Order (PO)
        Document: Purchase Order
        → Send PO to Supplier (cross-lane arrow to Supplier lane)

STEP 5  [Supplier]        Acknowledge PO
        → Confirm delivery date
        → Prepare goods/services

STEP 6  [Supplier]        Ship Goods / Deliver Service
        Document: Packing Slip / Delivery Note

STEP 7  [Requester]       Receive and Inspect Goods
        Document: Goods Receipt (GR) note
        DECISION GATEWAY: "Goods Acceptable?"
        → YES: Post GR → forward to AP
        → NO: Reject goods → notify Supplier (LOOP BACK to Step 6)

STEP 8  [Supplier]        Issue Invoice
        Document: Invoice
        → Send invoice to Accounts Payable

STEP 9  [Accounts Payable] 3-Way Match Verification
        Compare: PO (Step 4) vs. GR (Step 7) vs. Invoice (Step 8)
        DECISION GATEWAY: "3-Way Match Passes?"
        → YES: Approve invoice → schedule payment
        → NO: Invoice exception → contact Supplier (LOOP BACK to Step 8)

STEP 10 [Accounts Payable] Post Invoice to Accounting System
        → Record liability in ERP (SAP/Oracle)

STEP 11 [Finance/Treasury] Payment Authorization
        DECISION GATEWAY: "Payment Approved?" (for amounts > $50,000)
        → YES: Authorize payment run
        → NO: Escalate for additional approval (parallel review branch)

STEP 12 [Finance/Treasury] Execute Payment
        Payment method: ACH / Wire Transfer / Check
        Document: Payment Remittance Advice

STEP 13 [Accounts Payable] Send Remittance Advice to Supplier

STEP 14 [Supplier]        Reconcile Payment
        → Confirm receipt → Close invoice

[END EVENT] — P2P cycle complete

PARALLEL FLOWS REQUIRED
------------------------
- Steps 3-4 can run in parallel with vendor onboarding if new supplier
- Steps 9 (3-way match) can run partially in parallel with Step 10

KEY PERFORMANCE INDICATORS (for Page 2 - KPI Dashboard)
---------------------------------------------------------
1. P2P Cycle Time:           Target < 30 days (from PR creation to supplier payment)
2. First-Pass Match Rate:    Target > 90%   (invoices matching PO/GR on first try)
3. PO Compliance Rate:       Target > 95%   (spend under PO vs. total spend)
4. Invoice Exception Rate:   Target < 5%    (invoices requiring manual intervention)
5. On-Time Payment Rate:     Target > 98%   (payments made within agreed terms)
6. Cost per Invoice:         Target < $5.00 (fully-loaded AP processing cost)
7. Supplier Lead Time:       Varies by category (tracked for continuous improvement)

OUTPUT FILES
------------
~/Desktop/p2p_process.drawio   (draw.io source diagram)
~/Desktop/p2p_process.pdf      (PDF export for process audit presentation)
SPECEOF

chown ga:ga /home/ga/Desktop/p2p_process_spec.txt 2>/dev/null || true
echo "P2P spec file created: /home/ga/Desktop/p2p_process_spec.txt"

INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count
date +%s > /tmp/task_start_timestamp

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_p2p.log 2>&1 &"

echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

DISPLAY=:1 import -window root /tmp/p2p_start.png 2>/dev/null || true

echo "=== Setup complete: p2p_process_spec.txt on Desktop, draw.io running ==="
