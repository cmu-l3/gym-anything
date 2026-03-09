#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medical Billing Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents"
BILLS_DIR="$WORKSPACE_DIR/Medical_Bills"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$BILLS_DIR"

echo "Creating medical billing reference documents..."

# Create hospital bill
cat > "$BILLS_DIR/hospital_bill.txt" << 'EOF'
═══════════════════════════════════════════════════════════════
                    MEMORIAL HOSPITAL
                   PATIENT BILLING STATEMENT
═══════════════════════════════════════════════════════════════

Patient: [Your Name]
Account #: MH-2024-78451
Service Date: October 15, 2024
Statement Date: December 20, 2024

SERVICE DETAILS:
─────────────────────────────────────────────────────────────
Outpatient Surgery - General                    $2,847.00
Operating Room Facilities                       
Surgical Supplies                               
Recovery Room Care                              
─────────────────────────────────────────────────────────────

BILLING SUMMARY:
Total Charges:                                  $2,847.00
Insurance Adjustment:                          -$1,390.70
Insurance Payment:                             -$1,164.24
Previous Patient Payment:                        -$150.00

AMOUNT DUE FROM PATIENT:                        $1,200.00

*** PAYMENT DUE BY: January 5, 2025 ***

Please remit payment to avoid collection action.

For questions, call: 1-800-555-BILL
═══════════════════════════════════════════════════════════════
EOF

# Create insurance EOB (Explanation of Benefits)
cat > "$BILLS_DIR/insurance_eob.txt" << 'EOF'
═══════════════════════════════════════════════════════════════
                 BLUECROSS BLUESHIELD
              EXPLANATION OF BENEFITS (EOB)
═══════════════════════════════════════════════════════════════

Claim #: BC-2024-9876543
Patient: [Your Name]
Service Date: October 15, 2024
Processed: November 8, 2024

CLAIM DETAILS:
─────────────────────────────────────────────────────────────
Provider: Memorial Hospital
Service: Outpatient Surgery

Amount Billed by Provider:                      $2,847.00
Amount Allowed by Plan:                         $1,456.30
Amount Not Allowed (write-off):                 $1,390.70
Applied to Deductible:                            $150.00
Plan Pays (80% after deductible):               $1,164.24
You May Owe Provider:                             $292.06
─────────────────────────────────────────────────────────────

Provider: Associated Anesthesiology Group
Service: Anesthesia Services

Amount Billed by Provider:                        $650.00
Amount Allowed by Plan:                           $520.00
Amount Not Allowed (write-off):                   $130.00
Applied to Deductible:                              $0.00
Plan Pays (80%):                                  $416.00
You May Owe Provider:                             $104.00
─────────────────────────────────────────────────────────────

PAYMENT SUMMARY:
Total Amount Billed:                            $3,497.00
Total Amount Allowed:                           $1,976.30
Total Paid by Insurance:                        $1,580.24
Total Patient Responsibility:                     $396.06

Your deductible remaining: $0.00
Out-of-pocket max remaining: $4,850.00

For questions: 1-800-555-BCBS
═══════════════════════════════════════════════════════════════
EOF

# Create payment record
cat > "$BILLS_DIR/payment_record.txt" << 'EOF'
═══════════════════════════════════════════════════════════════
              YOUR PAYMENT HISTORY
              (from bank statements)
═══════════════════════════════════════════════════════════════

Date: October 22, 2024
Payee: Memorial Hospital
Check #: 1847
Amount: $150.00
Memo: "Surgery - Deductible payment"
Status: CLEARED

─────────────────────────────────────────────────────────────

Date: November 12, 2024
Payee: Associated Anesthesiology
Check #: 1853
Amount: $0.00
Note: Anesthesia bill not yet paid - waiting for insurance

─────────────────────────────────────────────────────────────

IMPORTANT NOTE:
You paid $150 to the hospital in October when they asked for 
your deductible at the time of service. This was BEFORE 
insurance processed the claim.

The current hospital bill of $1,200 does NOT seem to account 
for this payment or the insurance payment correctly!
═══════════════════════════════════════════════════════════════
EOF

# Create scenario summary
cat > "$BILLS_DIR/scenario_summary.txt" << 'EOF'
═══════════════════════════════════════════════════════════════
        MEDICAL BILLING DISPUTE - QUICK REFERENCE
═══════════════════════════════════════════════════════════════

THE PROBLEM:
Memorial Hospital sent you a bill claiming you owe $1,200.00.
This seems wrong! Your insurance EOB says something different.

KEY NUMBERS TO USE IN YOUR SPREADSHEET:
─────────────────────────────────────────────────────────────
PROVIDER CHARGES:
  Hospital:
    - Billed: $2,847.00
    - Insurance Allowed: $1,456.30
    - Write-off: $1,390.70
  
  Anesthesiologist:
    - Billed: $650.00
    - Insurance Allowed: $520.00
    - Write-off: $130.00

PAYMENTS MADE:
  - Insurance paid: $1,580.24 (note: EOB shows $1,164.24 to 
    hospital + $416.00 to anesthesiologist = $1,580.24 total)
  - You already paid: $150.00 (to hospital in October)

RECONCILIATION:
  Total Insurance Allowed: $1,976.30
  Total Already Paid: $1,730.24
  What You ACTUALLY Owe: $246.06
  
  What Hospital CLAIMS You Owe: $1,200.00
  DISCREPANCY TO DISPUTE: $953.94

─────────────────────────────────────────────────────────────
YOUR TASK:
Create a spreadsheet that clearly shows this discrepancy so you
can reference it during your phone call to the billing dept.

Organize it into 3 sections:
1. Provider Charges (who billed what, what insurance allowed)
2. Payment Breakdown (what's been paid already)  
3. Reconciliation (what you actually owe vs. what they claim)

Use formulas to calculate totals and the discrepancy.
Make important numbers BOLD.
Make the discrepancy amount RED so it stands out.
═══════════════════════════════════════════════════════════════
EOF

chown ga:ga "$BILLS_DIR"/*.txt

echo "✅ Reference documents created in: $BILLS_DIR"

# Create the empty template spreadsheet
SHEET_PATH="$WORKSPACE_DIR/medical_billing_dispute.xlsx"

cat > /tmp/create_billing_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Billing Dispute"

# Set column widths for readability
ws.column_dimensions['A'].width = 30
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 18

# Add a helpful instruction at the top
ws['A1'] = "MEDICAL BILLING RECONCILIATION"
ws['A1'].font = Font(bold=True, size=14)

ws['A2'] = "Reference documents are in: /home/ga/Documents/Medical_Bills/"
ws['A2'].font = Font(italic=True, size=9)

ws['A4'] = "Create your reconciliation below. Organize into 3 sections:"
ws['A5'] = "1. Provider Charges (starting around row 7)"
ws['A6'] = "2. Payment Breakdown (starting around row 12)"  
ws['A7'] = "3. Reconciliation (starting around row 17)"

# Add some visual spacing
ws['A9'] = "--- START YOUR WORK BELOW THIS LINE ---"
ws['A9'].font = Font(italic=True)

wb.save(sys.argv[1])
print(f"Template spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_billing_sheet.py
python3 /tmp/create_billing_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Template spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_billing_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_billing_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Medical Billing Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You had outpatient surgery. The hospital is billing you $1,200,"
echo "  but according to your insurance EOB, you should owe much less."
echo "  Before calling to dispute, create a reconciliation spreadsheet."
echo ""
echo "📁 Reference documents available at:"
echo "  /home/ga/Documents/Medical_Bills/"
echo "    - hospital_bill.txt"
echo "    - insurance_eob.txt"
echo "    - payment_record.txt"
echo "    - scenario_summary.txt"
echo ""
echo "✅ TO COMPLETE THIS TASK:"
echo "  1. Review the reference documents"
echo "  2. Create Section 1: Provider Charges"
echo "     - Headers: Provider | Billed Amount | Insurance Allowed | Difference"
echo "     - Hospital row, Anesthesiologist row, TOTAL row with formulas"
echo "  3. Create Section 2: Payment Breakdown"
echo "     - Headers: Payment Source | Amount | Date Noted"
echo "     - Insurance payment, Your payment, TOTAL row with formula"
echo "  4. Create Section 3: Reconciliation"
echo "     - Total Insurance Allowed (from Section 1)"
echo "     - Total Paid (from Section 2)"
echo "     - ACTUAL AMOUNT OWED (formula: Allowed - Paid) in BOLD"
echo "     - What Hospital Claims I Owe"
echo "     - DISCREPANCY TO DISPUTE (formula: Claimed - Actual) in BOLD and RED"
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: Use SUM formulas for totals, cell references for reconciliation"
echo ""