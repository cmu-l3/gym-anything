#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medical EOB Decoder Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw EOB data file
EOB_RAW_PATH="$WORKSPACE_DIR/eob_raw_data.txt"

cat > "$EOB_RAW_PATH" << 'EOBEOF'
EXPLANATION OF BENEFITS - Member ID: 847392Q
Insurance: BlueShield HealthPlus
Statement Date: 04/01/2024
Patient: Sarah Mitchell

================================================================================
RECENT MEDICAL SERVICES - SUMMARY
================================================================================

Date of Service | Provider Name              | Proc Code | Billed   | Allowed  | Paid by Plan | Patient Resp | Status
03/15/2024      | METRO EMERGENCY PHYS       | 99285     | 892.00   | 634.00   | 507.20       | 126.80       | PROCESSED
03/15/2024      | CITY HOSPITAL LAB          | 85025     | 156.00   | 156.00   | 0.00         | 156.00       | DENIED - NOT MEDICALLY NECESSARY
03/15/2024      | CITY HOSPITAL ER           | 99285     | 1450.00  | 1200.00  | 960.00       | 240.00       | PROCESSED
03/22/2024      | DR SINGH OPHTHALMOLOGY     | 92004     | 425.00   | 310.00   | 248.00       | 62.00        | PROCESSED
03/22/2024      | DR SINGH OPHTHALMOLOGY     | 92134     | 380.00   | 285.00   | 0.00         | 285.00       | DENIED - PRE-AUTH REQUIRED

================================================================================
FINANCIAL SUMMARY
================================================================================
TOTAL BILLED:           $3,303.00
TOTAL ALLOWED:          $2,585.00
PLAN PAID:              $1,715.20
YOU OWE:                $847.32

IMPORTANT INFORMATION:
- Your deductible for 2024 has been met: $0.00 remaining
- Out-of-pocket maximum: $3,850.00 (current year-to-date: $2,341.00)
- Denied claims may be appealed within 30 days from statement date
- Co-insurance rate: 20% after deductible

NOTES:
- Blood work (85025) was denied as not medically necessary per policy guidelines
- Imaging study (92134) requires pre-authorization for coverage
- If you disagree with any determination, call Member Services at 1-800-555-0199

For questions about this EOB, please call Member Services.
EOBEOF

chown ga:ga "$EOB_RAW_PATH"
echo "✅ Created EOB raw data: $EOB_RAW_PATH"

# Create the CPT codes reference file
CPT_REF_PATH="$WORKSPACE_DIR/cpt_codes_reference.txt"

cat > "$CPT_REF_PATH" << 'CPTEOF'
COMMON MEDICAL PROCEDURE CODES (CPT) - QUICK REFERENCE

Emergency Services:
99285 - Emergency Department Visit, High Complexity
        (Typically includes examination, diagnosis, and treatment planning
         for urgent or potentially life-threatening conditions)

Ophthalmology:
92004 - Ophthalmological Examination, New Patient, Comprehensive
        (Complete eye exam including history, visual acuity, refraction)
92134 - Computerized Ophthalmic Diagnostic Imaging
        (Retinal imaging, OCT scan, or similar diagnostic imaging)

Laboratory:
85025 - Complete Blood Count (CBC) with Differential
        (Measures red cells, white cells, platelets, hemoglobin, etc.)
85027 - Complete Blood Count (CBC) without Differential
80053 - Comprehensive Metabolic Panel (CMP)
83036 - Hemoglobin A1C (diabetes monitoring)

Radiology:
71046 - Chest X-Ray, 2 views
73610 - Ankle X-Ray, complete
70450 - CT Head without contrast

NOTE: Codes starting with 99xxx are evaluation/management services
      Codes starting with 80xxx-89xxx are laboratory services
      Codes starting with 70xxx-79xxx are radiology services
      Codes starting with 92xxx are ophthalmology/optometry services
CPTEOF

chown ga:ga "$CPT_REF_PATH"
echo "✅ Created CPT codes reference: $CPT_REF_PATH"

# Create a blank starter spreadsheet with minimal structure
SHEET_PATH="$WORKSPACE_DIR/EOB_Decoded_2024.xlsx"

cat > /tmp/create_eob_starter.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "EOB Analysis"

# Add a header row with instructions
ws['A1'] = "Medical EOB Decoder - Insurance Billing Analysis"
ws['A1'].font = Font(bold=True, size=14)

ws['A2'] = "Instructions: Organize the EOB data from eob_raw_data.txt into a clear table below."
ws['A2'].font = Font(italic=True, size=10)

ws['A3'] = "Reference: Use cpt_codes_reference.txt to decode medical procedure codes."
ws['A3'].font = Font(italic=True, size=10)

# Add some blank rows for working space
ws['A5'] = "START YOUR TABLE HERE:"
ws['A5'].font = Font(bold=True)

# Add suggested column headers (optional - user can modify)
headers = ['Date', 'Provider', 'Procedure Description', 'Code', 'Billed', 'Allowed', 'Paid by Plan', 'Patient Owes', 'Status/Notes']
for idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=6, column=idx)
    cell.value = header
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")
    cell.alignment = Alignment(horizontal='center')

# Set column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 30
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 14
ws.column_dimensions['H'].width = 14
ws.column_dimensions['I'].width = 35

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_eob_starter.py
python3 /tmp/create_eob_starter.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Created starter spreadsheet: $SHEET_PATH"

# Also create desktop shortcuts to the reference files for easy access
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create a text file on desktop with quick instructions
cat > "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt" << 'INSTEOF'
MEDICAL EOB DECODER TASK
========================

YOUR GOAL:
Create a clear spreadsheet that decodes the confusing insurance EOB.

FILES YOU NEED:
1. /home/ga/Documents/eob_raw_data.txt (the confusing EOB)
2. /home/ga/Documents/cpt_codes_reference.txt (procedure code meanings)
3. /home/ga/Documents/EOB_Decoded_2024.xlsx (your working spreadsheet - already open)

WHAT TO DO:
1. Extract all 5 line items from the EOB into organized rows
2. Add human-readable descriptions for procedure codes (use reference file)
3. Calculate accurate totals (you'll find a $22.48 discrepancy!)
4. Highlight/flag the 2 denied claims
5. Create a "Questions for Insurance" section with at least 3 specific questions

KEY INSIGHT:
The EOB says "YOU OWE: $847.32" but if you add up the Patient Resp column,
you get $869.80! That's a $22.48 discrepancy you need to identify.

DENIED CLAIMS TO FLAG:
- Blood work (85025): Denied as "not medically necessary"
- Eye imaging (92134): Denied - "pre-auth required"

SAVE YOUR WORK:
Press Ctrl+S when done!

Good luck!
INSTEOF

chown ga:ga "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt"

echo "✅ Created task instructions on desktop"

# Launch ONLYOFFICE with the starter spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_eob_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_eob_task.log || true
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

echo "=== Medical EOB Decoder Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You received a confusing medical insurance EOB (Explanation of Benefits)."
echo "  Multiple charges don't look right, and you have 30 days to dispute."
echo ""
echo "📂 FILES CREATED:"
echo "  - EOB raw data: $EOB_RAW_PATH"
echo "  - CPT codes reference: $CPT_REF_PATH"
echo "  - Working spreadsheet: $SHEET_PATH (already open)"
echo "  - Instructions: $DESKTOP_DIR/TASK_INSTRUCTIONS.txt"
echo ""
echo "✅ TASK REQUIREMENTS:"
echo "  1. Extract all 5 EOB line items into organized rows"
echo "  2. Decode procedure codes (99285, 85025, 92004, 92134) into plain English"
echo "  3. Calculate totals and identify the $22.48 billing discrepancy"
echo "  4. Flag the 2 denied claims (blood work and imaging)"
echo "  5. Create a Questions section with at least 3 items for insurance call"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 HINT: The EOB claims you owe $847.32, but line items add up to $869.80!"
echo ""