#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apartment Condition Dispute Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments/apartment_dispute"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create move-in notes file (reference material)
MOVE_IN_NOTES="$WORKSPACE_DIR/move_in_notes.txt"

sudo -u ga tee "$MOVE_IN_NOTES" > /dev/null <<'EOF'
MOVE-IN NOTES - Unit 4B - January 15, 2023
==========================================

Kitchen:
- Cabinet door under sink already has visible crack in corner (about 2 inches)
- Some water damage visible on cabinet floor from previous leak
- Countertop has minor scratches (looks normal for age)
- Took photos of cabinet damage on move-in day

Bedroom:
- Carpet has faint stains near closet area (looked old/set-in)
- Noted these stains on official move-in checklist
- Landlord acknowledged them during walkthrough
- Some general wear on carpet edges

Bathroom:
- Grout between tiles is yellowish/dingy looking
- Asked landlord about deep cleaning - he said "it's just old grout, normal"
- Shower head has mineral buildup
- Caulking around tub slightly discolored

Living Room:
- A few scuff marks on wall near front door
- Paint is slightly faded overall (especially near windows)
- Noticed during initial walkthrough
- Baseboards have some wear

Windows:
- Screen in bedroom window has small tear (approximately 1 inch)
- Landlord said he would fix it before we moved in but never did
- Mentioned this in email to landlord on Jan 20, 2023
- All window locks work fine

General Notes:
- Apartment is old but was clean when we moved in
- Some wear and tear is clearly from previous tenants
- Took extensive photos during move-in walkthrough
- Overall condition documented on move-in checklist
EOF

# Create landlord charges file (dispute basis)
LANDLORD_CHARGES="$WORKSPACE_DIR/landlord_charges.txt"

sudo -u ga tee "$LANDLORD_CHARGES" > /dev/null <<'EOF'
SECURITY DEPOSIT DEDUCTION NOTICE
Unit 4B - Tenant: Sam Johnson
Move-out Date: July 31, 2024
==================================

The following deductions will be made from your security deposit of $1,200:

1. Kitchen cabinet damage (crack and water damage): $250
   - Replace damaged cabinet door and repair water damage

2. Bedroom carpet staining: $180
   - Professional deep cleaning required for stains

3. Bathroom grout replacement: $150
   - Complete bathroom grout removal and replacement

4. Living room wall repainting (scuff marks): $120
   - Repaint living room walls due to excessive scuffing

5. Window screen replacement: $45
   - Replace torn bedroom window screen

6. General cleaning fee: $55
   - Additional cleaning required throughout unit

TOTAL DEDUCTIONS: $800

Remaining deposit to be returned: $400

A check for $400 will be mailed to you within 30 days.
You have 14 days from receipt of this notice to dispute these charges.

Property Manager
Oakview Apartments
EOF

# Create initial output document (minimal starting point)
DOC_PATH="$WORKSPACE_DIR/output.docx"

cat > /tmp/create_dispute_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a single paragraph as placeholder to ensure valid document
p = doc.add_paragraph()
p.add_run("Start your apartment condition dispute document here.")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_dispute_doc.py
python3 /tmp/create_dispute_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

# Set proper permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo chmod -R 755 "$WORKSPACE_DIR"

echo "✅ Task files created:"
echo "   - Move-in notes: $MOVE_IN_NOTES"
echo "   - Landlord charges: $LANDLORD_CHARGES"
echo "   - Output document: $DOC_PATH"

# Launch ONLYOFFICE with the output document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_dispute_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_dispute_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo ""
echo "=== Apartment Condition Dispute Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SCENARIO: You are disputing $800 in security deposit deductions."
echo "Reference files are available at:"
echo "  • $MOVE_IN_NOTES"
echo "  • $LANDLORD_CHARGES"
echo ""
echo "CREATE A PROFESSIONAL DISPUTE DOCUMENT WITH:"
echo ""
echo "1. HEADER (centered and bold):"
echo "   • Title: 'Apartment Condition Dispute - Unit 4B'"
echo "   • Subtitle: 'Move-in: January 15, 2023 | Move-out: July 31, 2024'"
echo ""
echo "2. INTRODUCTION PARAGRAPH:"
echo "   • State that many charges are for pre-existing damage"
echo "   • Reference supporting documentation"
echo "   • Use professional but firm tone"
echo ""
echo "3. COMPARISON TABLE (5 columns):"
echo "   Headers: Location/Item | Move-In Condition | Move-Out Condition | Disputed Charge | Our Position"
echo "   Include rows for:"
echo "   • Kitchen cabinet damage"
echo "   • Bedroom carpet stains"
echo "   • Bathroom grout discoloration"
echo "   • Living room wall scuff marks"
echo "   • Window screen condition"
echo ""
echo "4. SUMMARY SECTION (bold heading):"
echo "   • Title: 'Summary of Disputed Charges'"
echo "   • Total disputed amount ($800)"
echo "   • Statement about normal wear and tear"
echo "   • Request for revised charges"
echo ""
echo "5. Save the document (Ctrl+S)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"