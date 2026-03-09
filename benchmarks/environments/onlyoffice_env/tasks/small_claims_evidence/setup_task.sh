#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Small Claims Evidence Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the evidence items text file on Desktop
EVIDENCE_FILE="$DESKTOP_DIR/evidence_items.txt"

cat > "$EVIDENCE_FILE" << 'EVIDEOF'
SECURITY DEPOSIT DISPUTE EVIDENCE - ORGANIZE THIS!
==================================================

Your landlord withheld your $1,200 security deposit claiming damages.
You need to organize this evidence for small claims court next week.

EVIDENCE ITEMS (in scrambled order - you need to organize chronologically):

1. Move-in photos showing kitchen countertop already cracked (03/15/2024)
2. Lease agreement - security deposit amount was $1,200 (03/01/2024)
3. Professional cleaning service receipt - paid $180 (05/28/2024)
4. Email from landlord after move-out: "everything looks good" (05/28/2024)
5. Text from landlord claiming $800 for countertop replacement (06/03/2024)
6. Your text reply with move-in photo attached proving pre-existing damage (06/03/2024)
7. Bank statement showing security deposit payment (03/01/2024)
8. Certified mail receipt for demand letter to landlord (06/10/2024)
9. Email from previous tenant: "Yes, that crack was there when I lived there too" (03/10/2024)
10. Photos of clean empty apartment taken on move-out day (05/28/2024)

LANDLORD'S CLAIMS:
- $800 for countertop replacement
- $200 for cleaning (even though you paid $180 for professional cleaning!)

YOUR GOAL: Get your full $1,200 deposit back.

WHAT YOU NEED TO PROVE:
a) Countertop damage was pre-existing (not your responsibility)
b) Apartment was professionally cleaned (you have receipt)
c) Landlord acknowledged good condition at move-out (email evidence)

TASK INSTRUCTIONS:
==================
1. Create a spreadsheet with columns:
   - Date
   - Evidence Type (Photo, Receipt, Email, Text Message, Witness, Document)
   - Description
   - Supports Claim
   - Dollar Amount (if applicable)
   - Days Since Move-In

2. Enter all 10 evidence items in CHRONOLOGICAL ORDER (earliest first)
   Move-in date was March 1, 2024 - use this as day 0

3. Calculate "Days Since Move-In" for each evidence item

4. Create a SUMMARY SECTION below your evidence with:
   - Total security deposit paid: $1,200
   - Landlord's claimed deductions: $1,000 total ($800 + $200)
   - Your documented cleaning expense: $180
   - Amount you should recover: $1,200 (full deposit)

5. Apply CONDITIONAL FORMATTING:
   - Highlight rows about PRE-EXISTING damage in LIGHT GREEN
   - Highlight the move-out walkthrough row in LIGHT YELLOW
   - Highlight landlord's damage CLAIMS in LIGHT RED

6. Save the file as: /home/ga/Documents/Spreadsheets/deposit_evidence.xlsx

This organized evidence log will help the judge quickly understand your case!
EVIDEOF

chown ga:ga "$EVIDENCE_FILE"

echo "✅ Evidence items file created at: $EVIDENCE_FILE"

# Create a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/deposit_evidence.xlsx"

cat > /tmp/create_evidence_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Evidence Log"

# Add instructional header
ws['A1'] = "Security Deposit Dispute - Evidence Organization"
ws['A1'].font = Font(bold=True, size=14)

ws['A2'] = "Instructions: See Desktop/evidence_items.txt for details. Create your evidence log below."
ws['A2'].font = Font(italic=True, size=10)

# Leave some space for user to create their own structure
# User should create headers and enter data themselves

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_evidence_sheet.py
python3 /tmp/create_evidence_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_claims_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_claims_task.log || true
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

# Open the evidence text file in a text editor for reference
echo "Opening evidence items file for reference..."
su - ga -c "DISPLAY=:1 gedit '$EVIDENCE_FILE' > /dev/null 2>&1 &" || \
su - ga -c "DISPLAY=:1 xdg-open '$EVIDENCE_FILE' > /dev/null 2>&1 &" || true

sleep 2

# Refocus ONLYOFFICE
focus_onlyoffice_window

echo "=== Small Claims Evidence Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You're preparing for small claims court next week to recover your"
echo "  wrongfully withheld $1,200 security deposit."
echo ""
echo "📝 TASK:"
echo "  1. Read the evidence items from Desktop/evidence_items.txt"
echo "  2. Create a structured evidence log with required columns"
echo "  3. Enter all 10 evidence items in chronological order"
echo "  4. Calculate days since move-in (March 1, 2024 = day 0)"
echo "  5. Create a summary section with financial calculations"
echo "  6. Apply conditional formatting (green/yellow/red highlights)"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: The evidence file is open in a text editor for your reference."
echo "    Focus between windows to copy information."