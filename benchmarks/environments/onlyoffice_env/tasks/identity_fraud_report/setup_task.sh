#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Identity Fraud Report Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create fraud notes reference file on Desktop
NOTES_PATH="/home/ga/Desktop/fraud_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
FRAUD DISCOVERED - MAY 22, 2024

MY CARD: ending in 7834
MY NAME: Alex Rivera

FAKE CHARGES I DIDN'T MAKE:
- GameStopPlus Online: $249.99 on May 19
- Premium_Kicks_NYC: $389.00 on May 19 (NEW YORK?? I'm in California!)
- DigiKeys Electronics: $156.43 on May 20  
- FastGas Station: $75.00 on May 21 (LAS VEGAS - I don't even have a car!)
- LuxuryFragrance.com: $212.88 on May 21

TOTAL FRAUD: $1,083.30

LAST REAL PURCHASE I MADE:
May 18 - Safeway groceries $87.32 (this one is legit)

WHAT I DID:
- May 22, 7:15am: Got email alert about $389 charge
- May 22, 7:30am: Checked account, found ALL the fraud charges
- May 22, 8:00am: Called bank fraud line - got reference # FR-2024-05-8834
- May 22, 8:15am: They deactivated my card
- May 22, 2pm: Filed online dispute
- May 23: Changed all my passwords 
- May 23: Called credit bureaus to put fraud alert

Need to turn this into formal report for bank fraud department!
EOF

chown ga:ga "$NOTES_PATH"
chmod 644 "$NOTES_PATH"

echo "✅ Fraud notes created at: $NOTES_PATH"

# Create empty starting document
DOC_PATH="$WORKSPACE_DIR/fraud_report.docx"

cat > /tmp/create_fraud_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Create a blank document with minimal placeholder
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank fraud report document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_fraud_doc.py
python3 /tmp/create_fraud_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank fraud report document created at: $DOC_PATH"

# Launch ONLYOFFICE with the blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_fraud_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_fraud_task.log || true
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

echo "=== Identity Fraud Report Task Setup Complete ==="
echo ""
echo "🚨 SCENARIO: You discovered fraudulent credit card charges and need to create"
echo "   a formal fraud report for your bank's fraud investigation department."
echo ""
echo "📋 Reference material available at: /home/ga/Desktop/fraud_notes.txt"
echo "   (Contains rough notes about the fraud - transform into professional report)"
echo ""
echo "🎯 CREATE A PROFESSIONAL FRAUD REPORT with:"
echo ""
echo "   1. DOCUMENT HEADER (centered, bold, 16pt):"
echo "      - Title: 'FRAUD REPORT STATEMENT'"
echo "      - Credit Card Account: **** **** **** 7834"
echo "      - Cardholder: Alex Rivera"
echo "      - Report Date"
echo ""
echo "   2. ALL FIVE FRAUDULENT TRANSACTIONS:"
echo "      - GameStopPlus Online: \$249.99 (May 19, 2024)"
echo "      - Premium_Kicks_NYC: \$389.00 (May 19, 2024 - New York, NY)"
echo "      - DigiKeys Electronics: \$156.43 (May 20, 2024)"
echo "      - FastGas Station: \$75.00 (May 21, 2024 - Las Vegas, NV)"
echo "      - LuxuryFragrance.com: \$212.88 (May 21, 2024)"
echo ""
echo "   3. TOTAL FRAUDULENT AMOUNT: \$1,083.30 (make this BOLD)"
echo ""
echo "   4. TIMELINE OF DISCOVERY AND RESPONSE:"
echo "      - May 22, 7:15 AM - Discovered fraud via email alert"
echo "      - May 22, 8:00 AM - Called bank (Reference: FR-2024-05-8834)"
echo "      - May 22, 8:15 AM - Card deactivated"
echo "      - May 22, 2:00 PM - Filed online dispute"
echo "      - May 23 - Changed passwords, contacted credit bureaus"
echo "      (Make dates BOLD for easy scanning)"
echo ""
echo "   5. LAST LEGITIMATE TRANSACTION:"
echo "      - May 18, 2024 - Safeway groceries \$87.32"
echo ""
echo "   6. DECLARATION STATEMENT:"
echo "      - Formal declaration of truthfulness"
echo "      - Signature and date lines"
echo ""
echo "📐 FORMATTING:"
echo "   - Title: centered, bold, 16pt"
echo "   - Section headings: bold, 14pt"
echo "   - Dates in timeline: bold"
echo "   - Total amount: bold"
echo "   - Professional, formal tone"
echo ""
echo "💾 SAVE: Save as /home/ga/Documents/TextDocuments/fraud_report.docx (Ctrl+S)"
echo ""
echo "⏱️  This is urgent - fraud claims have legal deadlines!"