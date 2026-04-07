#!/bin/bash
set -euo pipefail

echo "=== Setting up Corporate MSA Formatting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
echo $(date +%s) > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Ensure directories exist
DOCS_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$DOCS_DIR"

INPUT_PATH="$DOCS_DIR/raw_msa_draft.docx"

# Generate the raw unformatted DOCX using Python
# (This ensures it has absolutely no existing styles/formatting applied yet)
cat > /tmp/create_raw_msa.py << 'PYEOF'
import docx
import sys

doc = docx.Document()

# Raw text for the MSA
paragraphs = [
    "MASTER SERVICE AGREEMENT",
    "This Master Service Agreement (the \"Agreement\") is made and entered into as of the Effective Date by and between the Client and the Service Provider.",
    "1. SERVICES AND DELIVERABLES",
    "1.1 Scope of Services",
    "The Service Provider shall perform the services and provide the Deliverables as specified in each Statement of Work mutually agreed upon by the parties.",
    "2. PAYMENT TERMS",
    "2.1 Invoicing",
    "Client shall pay all undisputed invoices within thirty (30) days of receipt. All payments under this Agreement are non-refundable.",
    "3. CONFIDENTIALITY",
    "3.1 Definition",
    "Confidential Information means any non-public information disclosed by one party to the other party, whether orally or in writing, that is designated as confidential.",
    "4. TERM AND TERMINATION",
    "4.1 Term",
    "This Agreement shall commence on the Effective Date and continue until terminated by either party with thirty days written notice.",
    "5. WARRANTIES",
    "5.1 Service Warranty",
    "Service Provider warrants that services will be performed in a professional and workmanlike manner consistent with industry standards.",
    "6. INDEMNIFICATION",
    "6.1 General Indemnity",
    "Each party agrees to indemnify and hold harmless the other party from any claims arising out of gross negligence or willful misconduct.",
    "7. MISCELLANEOUS",
    "7.1 Governing Law",
    "This Agreement shall be governed by the laws of the applicable jurisdiction without regard to conflict of laws principles."
]

for text in paragraphs:
    p = doc.add_paragraph(text)
    # Force Left alignment and Normal style to simulate a raw text dump
    p.alignment = 0 
    p.style = doc.styles['Normal']

doc.save(sys.argv[1])
PYEOF

sudo -u ga python3 /tmp/create_raw_msa.py "$INPUT_PATH"

# Launch ONLYOFFICE with the raw draft
echo "Launching ONLYOFFICE..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$INPUT_PATH" > /tmp/onlyoffice.log 2>&1 &

# Wait for ONLYOFFICE window to appear and stabilize
wait_for_window "ONLYOFFICE\|Desktop Editors" 30
sleep 5

# Maximize and Focus
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    echo "Focusing and maximizing ONLYOFFICE (WID: $WID)..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
fi

# Take initial screenshot showing the unformatted document
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="