#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Visa Document Timeline Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy visa requirements text file
REQUIREMENTS_PATH="$WORKSPACE_DIR/visa_requirements_raw.txt"

cat > "$REQUIREMENTS_PATH" << 'TXTEOF'
UK STUDENT VISA REQUIRED DOCUMENTS

Current valid passport (must have blank page)
Confirmation of Acceptance for Studies (CAS) from university - already received
Passport photos 2x - 45mm x 35mm color on white background, get at pharmacy £8
Financial proof - bank statements for last 28 days showing £15000+ (must be dated within 31 days of application)
Tuberculosis test certificate - book at approved clinic, takes 3 days for results, costs £85, valid 6 months
Police clearance certificate from home country - mail request form, takes 6-8 weeks, £50, valid 6 months only
Birth certificate original plus certified English translation (if not originally in English) - certified translation £40 per document, takes 2 weeks
Previous qualifications certificates (undergraduate degree) - need official translated copy £35, 2 weeks
English language test results (IELTS Academic) - test taken already, results valid 2 years
Proof of relationship to financial sponsor if parents paying (birth cert covers this)
Letter from financial sponsor if parents paying - need parent signature and notarization £15
Completed visa application form (online, no cost, 1 hour to complete)
IHS (Immigration Health Surcharge) payment receipt - £470/year for 3 years = £1410, pay online during application
Previous UK visa pages if any (n/a for first-time applicant)
Academic Technology Approval Scheme certificate if studying sensitive subject (not needed for Psychology)
Passport from last 10 years if have old expired one for travel history - stored at parents house, need to request

TOTAL WEEKS AVAILABLE: 12 weeks until program starts
VISA PROCESSING TIME: 3 weeks (must have ALL documents before applying)
APPOINTMENT BOOKING: Must be done 1 week before desired appointment date

IMPORTANT TIMING NOTES:
- Police certificate: 6-8 weeks lead time, only valid 6 months - DO THIS FIRST!
- Birth certificate translation: Need original first, then translate (2 weeks), then apostille
- Bank statements: Must be less than 31 days old at submission - get these LAST
- TB test: Results in 3 days, valid 6 months
- Must book visa appointment only after ALL documents ready
- Missing deadline means losing scholarship and deferring 1 year

ESTIMATED COSTS:
Passport photos: £8
TB test: £85
Police certificate: £50
Birth cert translation: £40
Degree translation: £35
Notarization: £15
IHS payment: £1410
Total estimated: ~£1643 + visa application fee

NOTE: Some documents have dependencies - you cannot translate something you don't have yet!
TXTEOF

chown ga:ga "$REQUIREMENTS_PATH"
echo "✅ Requirements text file created at: $REQUIREMENTS_PATH"

# Create an empty starter spreadsheet
SHEET_PATH="$WORKSPACE_DIR/visa_tracker.xlsx"

cat > /tmp/create_visa_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Visa Documents"

# Add a helpful header
ws['A1'] = "UK Student Visa Document Tracker"
ws['A1'].font = Font(size=14, bold=True)
ws['A1'].alignment = Alignment(horizontal='left')

ws['A2'] = "Instructions: Extract information from visa_requirements_raw.txt and organize it here"
ws['A2'].font = Font(size=10, italic=True)

ws['A3'] = "Include: document names, costs, timelines, validity periods, dependencies, and priorities"
ws['A3'].font = Font(size=10, italic=True)

# Leave rest blank for agent to fill
wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_visa_sheet.py
python3 /tmp/create_visa_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_visa_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "WARNING: ONLYOFFICE process not detected, but continuing..."
    cat /tmp/onlyoffice_visa_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "WARNING: ONLYOFFICE window not detected, but continuing..."
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Visa Document Timeline Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You've been accepted to a UK graduate program starting in September (12 weeks away)."
echo "  You need to organize your Student Visa application documents."
echo ""
echo "📝 YOUR TASK:"
echo "  1. Open and read: $REQUIREMENTS_PATH"
echo "  2. Create a tracking spreadsheet in: $SHEET_PATH"
echo "  3. Extract all required documents (at least 12 items)"
echo "  4. Create columns for: Document Name, Status, Cost, Time to Obtain, Validity Period, Dependencies/Priority"
echo "  5. Extract costs from the text and create a SUM formula for total cost"
echo "  6. Identify time-sensitive items (police cert: 6-8 weeks, translations: 2 weeks)"
echo "  7. Organize logically (by priority or deadline)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 KEY CHALLENGES:"
echo "  - Extract info from messy, prose-style text (not a structured list)"
echo "  - Identify which documents must be done first (dependencies)"
echo "  - Calculate total cost (~£1600-2000)"
echo "  - Flag items with long lead times or short validity periods"
echo ""
echo "⏰ TIME PRESSURE: You have 12 weeks total, visa processing takes 3 weeks"
echo "   → Only 9 weeks to gather ALL documents!"