#!/bin/bash
echo "=== Setting up Bilingual Legal Contract Formatting ==="
date +%s > /tmp/task_start_time.txt

# Create the unformatted draft document using python-docx
cat > /tmp/create_draft.py << 'EOF'
import sys
import os

try:
    from docx import Document
    from docx.shared import Pt
    from docx.enum.text import WD_ALIGN_PARAGRAPH
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "python-docx"])
    from docx import Document
    from docx.shared import Pt
    from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
table = doc.add_table(rows=0, cols=2)
table.style = 'Table Grid'

def add_row(text1, text2):
    row = table.add_row()
    row.cells[0].text = text1
    row.cells[1].text = text2
    for cell in row.cells:
        for p in cell.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            for r in p.runs:
                r.font.name = 'Arial'
                r.font.size = Pt(11)

def add_row_sigs(text1, text2):
    row = table.add_row()
    for i, texts in enumerate([text1.split('\n'), text2.split('\n')]):
        cell = row.cells[i]
        p = cell.paragraphs[0]
        p.text = texts[0]
        for t in texts[1:]:
            cell.add_paragraph(t)
        for p in cell.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            for r in p.runs:
                r.font.name = 'Arial'
                r.font.size = Pt(11)

add_row("MUTUAL NON-DISCLOSURE AGREEMENT", "ACUERDO DE CONFIDENCIALIDAD MUTUA")
add_row("This Mutual Non-Disclosure Agreement is entered into by the parties.", "Este Acuerdo de Confidencialidad Mutua es celebrado por las partes.")
add_row("1. Confidential Information\nThe term Confidential Information means all non-public data, business plans, and financial records.", 
        "1. Información Confidencial\nEl término Información Confidencial significa todos los datos no públicos, planes de negocios y registros financieros.")
add_row("2. Obligations\nThe receiving party shall not disclose any Confidential Information to third parties.", 
        "2. Obligaciones\nLa parte receptora no divulgará ninguna Información Confidencial a terceros.")
add_row_sigs("Signature: ____________________\nName: ____________________\nDate: ____________________", 
        "Firma: ____________________\nNombre: ____________________\nFecha: ____________________")

os.makedirs('/home/ga/Documents/TextDocuments', exist_ok=True)
doc.save('/home/ga/Documents/TextDocuments/bilingual_nda_draft.docx')
EOF

su - ga -c "python3 /tmp/create_draft.py"

# Start ONLYOFFICE Document Editor
su - ga -c "DISPLAY=:1 /usr/bin/onlyoffice-desktopeditors /home/ga/Documents/TextDocuments/bilingual_nda_draft.docx > /dev/null 2>&1 &"

# Wait for the application window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Desktop Editors\|ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="