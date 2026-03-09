#!/bin/bash
set -e
echo "=== Setting up Contract Redline Generation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate V1 and V2 contracts using python-docx
# We use python3 to generate clean DOCX files with specific content
python3 << 'EOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_contract(version="v1"):
    doc = Document()
    
    # Title
    title = doc.add_heading('MASTER SUPPLY AGREEMENT', 0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    
    doc.add_paragraph('This Agreement is made this 12th day of March, 2026, by and between:')
    doc.add_paragraph('APEX CONSTRUCTION, INC. ("Buyer") and SUPERIOR STEELWORKS, LLC ("Supplier").')
    
    # Article 1: Payment
    doc.add_heading('ARTICLE 1: PAYMENT TERMS', level=1)
    doc.add_paragraph('1.1 Invoices. Supplier shall invoice Buyer upon shipment of Goods.')
    
    p = doc.add_paragraph('1.2 Payment. Buyer shall pay all undisputed invoices within ')
    if version == "v1":
        run = p.add_run('Net 30')
    else:
        run = p.add_run('Net 60') # V2 Change
    run.bold = True
    p.add_run(' days from the date of receipt.')
    
    # Article 2: Liability
    doc.add_heading('ARTICLE 2: LIABILITY', level=1)
    doc.add_paragraph('2.1 Indemnification. Supplier agrees to indemnify Buyer against all claims arising from defective Goods.')
    
    p = doc.add_paragraph('2.2 Limitation of Liability. Supplier’s total liability under this Agreement shall not exceed ')
    if version == "v1":
        run = p.add_run('$1,000,000')
    else:
        run = p.add_run('$500,000') # V2 Change
    run.bold = True
    p.add_run(' in the aggregate.')
    
    # Article 3: Termination
    doc.add_heading('ARTICLE 3: TERMINATION', level=1)
    
    term_days = "15" if version == "v1" else "90" # V2 Change
    doc.add_paragraph(f'3.1 Termination for Convenience. Buyer may terminate this Agreement at any time upon {term_days} days written notice.')
    
    # Filler text to make it look real
    doc.add_heading('ARTICLE 4: MISCELLANEOUS', level=1)
    doc.add_paragraph('4.1 Governing Law. This Agreement shall be governed by the laws of the State of New York.')
    doc.add_paragraph('4.2 Entire Agreement. This document constitutes the entire agreement between the parties.')
    
    return doc

# Save V1
doc1 = create_contract("v1")
doc1.save('/home/ga/Documents/supply_agreement_v1_sent.docx')

# Save V2
doc2 = create_contract("v2")
doc2.save('/home/ga/Documents/supply_agreement_v2_vendor.docx')

print("Generated V1 and V2 contracts.")
EOF

# Set permissions
chown ga:ga /home/ga/Documents/supply_agreement_*.docx
chmod 666 /home/ga/Documents/supply_agreement_*.docx

# Start LibreOffice Writer with V1 open
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/supply_agreement_v1_sent.docx > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "supply_agreement_v1" 60 || echo "Warning: Window wait timeout"

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss potential "Tip of the Day" or recovery dialogs
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="