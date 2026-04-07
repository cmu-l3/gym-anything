#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bilingual Contract Alignment Task ==="

# Clean state
kill_calligra_processes
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
rm -f /home/ga/Documents/bilingual_mnda.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the initial sequential bilingual contract
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_p(text):
    doc.text.addElement(P(text=text))

add_p("MUTUAL NON-DISCLOSURE AGREEMENT / ACUERDO MUTUO DE CONFIDENCIALIDAD")
add_p("")

en_clauses = [
    "1. Confidential Information: The term \"Confidential Information\" shall mean any and all information disclosed by the Disclosing Party to the Receiving Party.",
    "2. Obligations: The Receiving Party shall hold and maintain the Confidential Information in strictest confidence for the sole and exclusive benefit of the Disclosing Party.",
    "3. Exclusions: Confidential Information does not include information that is or becomes publicly known through no fault of the Receiving Party.",
    "4. Term: This Agreement shall remain in effect for a period of three (3) years from the Effective Date.",
    "5. Return of Materials: Upon the written request of the Disclosing Party, the Receiving Party shall return all copies of the documents containing Confidential Information.",
    "6. Governing Law: This Agreement shall be governed by and construed in accordance with the laws of the State of Delaware.",
    "7. Signatures: IN WITNESS WHEREOF, the parties have executed this Agreement as of the Effective Date."
]

es_clauses = [
    "1. Información Confidencial: El término \"Información Confidencial\" significará toda y cualquier información revelada por la Parte Reveladora a la Parte Receptora.",
    "2. Obligaciones: La Parte Receptora mantendrá la Información Confidencial en la más estricta confidencialidad para el beneficio único y exclusivo de la Parte Reveladora.",
    "3. Exclusiones: La Información Confidencial no incluye información que es o se hace de dominio público sin culpa de la Parte Receptora.",
    "4. Plazo: Este Acuerdo permanecerá en vigor por un período de tres (3) años a partir de la Fecha Efectiva.",
    "5. Devolución de Materiales: A solicitud por escrito de la Parte Reveladora, la Parte Receptora devolverá todas las copias de los documentos que contengan Información Confidencial.",
    "6. Ley Aplicable: Este Acuerdo se regirá e interpretará de acuerdo con las leyes del Estado de Delaware.",
    "7. Firmas: EN FE DE LO CUAL, las partes han suscrito este Acuerdo a partir de la Fecha Efectiva."
]

for c in en_clauses:
    add_p(c)
    add_p("")

for c in es_clauses:
    add_p(c)
    add_p("")

doc.save("/home/ga/Documents/bilingual_mnda.odt")
PYEOF

chown ga:ga /home/ga/Documents/bilingual_mnda.odt

# Create the instructions file
cat > /home/ga/Desktop/alignment_instructions.txt << 'EOF'
CLIENT INSTRUCTIONS: BILINGUAL MNDA FORMATTING

Please format the draft MNDA into a standard side-by-side bilingual dual-column layout.

1. Create a 7-row, 2-column table below the main title.
2. Align the English clauses in the left column (Column 1).
3. Align the corresponding Spanish translations in the right column (Column 2).
   - E.g., Row 1: "Confidential Information" (EN) | "Información Confidencial" (ES)
   - Ensure all 7 clauses match semantically.
4. Delete the original sequential text once everything is in the table.
5. Format the main title ("MUTUAL NON-DISCLOSURE AGREEMENT / ACUERDO MUTUO DE CONFIDENCIALIDAD") as Heading 1 and Centered.
6. Justify the text inside the table cells.
7. Save the document.
EOF

chown ga:ga /home/ga/Desktop/alignment_instructions.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/bilingual_mnda.odt"

# Wait for and maximize window
wait_for_window "Calligra Words\|bilingual_mnda" 30
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial Evidence
sleep 1
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="