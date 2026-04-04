#!/bin/bash
set -e

echo "=== Setting up Legal Contract Review Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the contract files using python3 and odfpy
# We use a python script to ensure proper ODT structure
cat << 'PYEOF' > /tmp/generate_contracts.py
import os
from odf.opendocument import OpenDocumentText
from odf.text import P, H, Span
from odf.style import Style, TextProperties, ParagraphProperties

def create_doc(filename, version):
    doc = OpenDocumentText()
    
    # Create a heading style
    h1style = Style(name="Heading 1", family="paragraph")
    h1style.addElement(TextProperties(attributes={'fontsize':"14pt", 'fontweight':"bold"}))
    doc.styles.addElement(h1style)
    
    # Title
    doc.text.addElement(H(outlinelevel=1, stylename=h1style, text="SERVICE LEVEL AGREEMENT"))
    doc.text.addElement(P(text="This Agreement is entered into between Acme Corp ('Client') and DevSolutions Inc ('Provider')."))
    doc.text.addElement(P(text=""))

    # 1. Services
    doc.text.addElement(H(outlinelevel=2, text="1. Services"))
    doc.text.addElement(P(text="Provider agrees to perform IT consulting services as detailed in the Statement of Work."))
    doc.text.addElement(P(text=""))

    # 2. Payment Terms
    doc.text.addElement(H(outlinelevel=2, text="2. Payment Terms"))
    if version == "v1":
        doc.text.addElement(P(text="Invoices shall be payable within 30 days of receipt."))
    else:
        # Vendor changed this
        doc.text.addElement(P(text="Invoices shall be payable within 45 days of receipt."))
    doc.text.addElement(P(text=""))

    # 3. Limitation of Liability
    doc.text.addElement(H(outlinelevel=2, text="3. Limitation of Liability"))
    if version == "v1":
        doc.text.addElement(P(text="The total liability of either party shall not exceed $1,000,000."))
    else:
        # Vendor changed this
        doc.text.addElement(P(text="The total liability of either party shall not exceed $500,000."))
    doc.text.addElement(P(text=""))

    # 4. Arbitration (Deleted in v2)
    if version == "v1":
        doc.text.addElement(H(outlinelevel=2, text="4. Arbitration"))
        doc.text.addElement(P(text="Any dispute arising under this Agreement shall be resolved via binding arbitration in the State of New York."))
        doc.text.addElement(P(text=""))

    # 5. Force Majeure (Added in v2)
    if version == "v2":
        doc.text.addElement(H(outlinelevel=2, text="5. Force Majeure"))
        doc.text.addElement(P(text="Neither party shall be liable for delay caused by circumstances beyond its reasonable control, including acts of God, war, or terrorism."))
        doc.text.addElement(P(text=""))

    # Footer
    doc.text.addElement(P(text="Executed on ___________."))
    
    doc.save(filename)
    print(f"Created {filename}")

if __name__ == "__main__":
    create_doc("/home/ga/Documents/contract_v1_original.odt", "v1")
    create_doc("/home/ga/Documents/contract_v2_vendor.odt", "v2")
PYEOF

# Run the generation script
python3 /tmp/generate_contracts.py
rm /tmp/generate_contracts.py

# Set permissions
chown ga:ga /home/ga/Documents/contract_v1_original.odt
chown ga:ga /home/ga/Documents/contract_v2_vendor.odt

# Start LibreOffice Writer with the original document
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/contract_v1_original.odt > /dev/null 2>&1 &"

# Wait for window
wait_for_window "contract_v1" 60 || wait_for_window "Writer" 60

# Maximize
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="