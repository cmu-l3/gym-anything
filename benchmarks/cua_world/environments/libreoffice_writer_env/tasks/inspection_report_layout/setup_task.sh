#!/bin/bash
set -e
echo "=== Setting up Inspection Report Layout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents

# Create the source generation script
cat > /tmp/create_source_doc.py << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
import os

def create_inspection_report():
    doc = Document()
    style = doc.styles['Normal']
    style.font.name = 'Liberation Serif'
    style.font.size = Pt(11)

    # TITLE PAGE CONTENT
    for _ in range(3): doc.add_paragraph('')
    p = doc.add_paragraph("PROPERTY CONDITION ASSESSMENT")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.runs[0].bold = True
    p.runs[0].font.size = Pt(22)
    p.runs[0].font.name = 'Liberation Sans'
    
    doc.add_paragraph("1200 Industrial Parkway\nColumbus, OH 43204").alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph("")
    
    doc.add_paragraph("Prepared for:").alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph("Meridian Capital Real Estate Partners, LLC").alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph("")
    
    doc.add_paragraph("Prepared by:").alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph("ABC Engineering Associates").alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph("")
    
    doc.add_paragraph("PCA Report No. 2024-0847\nNovember 15, 2024").alignment = WD_ALIGN_PARAGRAPH.CENTER
    
    doc.add_page_break()

    # BODY CONTENT
    h = doc.add_paragraph("EXECUTIVE SUMMARY")
    h.runs[0].bold = True
    h.runs[0].font.size = Pt(16)
    
    doc.add_paragraph(
        "ABC Engineering Associates was retained to conduct a Property Condition Assessment (PCA) "
        "of the subject property located at 1200 Industrial Parkway. This assessment was performed "
        "in general conformance with ASTM E2018-15 standards."
    )
    doc.add_paragraph(
        "The subject property consists of a single-story industrial/warehouse facility constructed "
        "circa 1987. The facility encompasses approximately 148,000 square feet of gross building area."
    )
    
    h = doc.add_paragraph("1.0 SITE AND TOPOGRAPHY")
    h.runs[0].bold = True
    doc.add_paragraph("The subject site is an irregularly shaped parcel of approximately 8.7 acres.")
    
    h = doc.add_paragraph("2.0 STRUCTURAL FRAME")
    h.runs[0].bold = True
    doc.add_paragraph("The warehouse portion is of pre-engineered metal building (PEMB) construction.")

    doc.add_page_break()
    
    # APPENDIX A
    h = doc.add_paragraph("APPENDIX A: FLOOR PLANS AND DEFICIENCY MATRIX")
    h.runs[0].bold = True
    h.runs[0].font.size = Pt(16)
    
    doc.add_paragraph("The following matrix summarizes observed conditions requiring remediation.")
    
    # Wide table causing need for landscape
    table = doc.add_table(rows=5, cols=6)
    table.style = 'Table Grid'
    headers = ['Item', 'System', 'Deficiency Description', 'Severity', 'Action', 'Priority']
    for i, h_text in enumerate(headers):
        table.cell(0, i).text = h_text
    
    data = [
        ['D-01', 'Roofing', 'EPDM membrane past useful life', 'Critical', 'Full replacement', '1'],
        ['D-02', 'Structural', 'Column base plate corrosion', 'Minor', 'Clean and coat', '2'],
        ['D-03', 'HVAC', 'RTU replacement (4 units)', 'Moderate', 'Phased replacement', '2'],
        ['D-04', 'Electrical', 'Switchgear clearance violation', 'Moderate', 'Relocate materials', '1']
    ]
    for i, row_data in enumerate(data):
        for j, val in enumerate(row_data):
            table.cell(i+1, j).text = val

    doc.add_page_break()

    # APPENDIX B
    h = doc.add_paragraph("APPENDIX B: COST ESTIMATES")
    h.runs[0].bold = True
    h.runs[0].font.size = Pt(16)
    
    doc.add_paragraph("The following table presents opinion of probable costs.")
    
    # Another wide table
    table2 = doc.add_table(rows=5, cols=5)
    table2.style = 'Table Grid'
    headers2 = ['Item', 'Description', 'Immediate ($)', 'Short-Term ($)', 'Long-Term ($)']
    for i, h_text in enumerate(headers2):
        table2.cell(0, i).text = h_text
        
    data2 = [
        ['D-01', 'Roof replacement', '245,000', '—', '—'],
        ['D-02', 'Base plate repair', '—', '12,000', '—'],
        ['D-03', 'RTU replacement', '—', '185,000', '—'],
        ['Total', '', '245,000', '197,000', '—']
    ]
    for i, row_data in enumerate(data2):
        for j, val in enumerate(row_data):
            table2.cell(i+1, j).text = val

    doc.add_page_break()

    # APPENDIX C
    h = doc.add_paragraph("APPENDIX C: CERTIFICATIONS AND QUALIFICATIONS")
    h.runs[0].bold = True
    h.runs[0].font.size = Pt(16)
    
    doc.add_paragraph("I, James R. Thornton, P.E., hereby certify that I personally conducted the inspection.")
    doc.add_paragraph("James R. Thornton, P.E.\nOhio License No. 68742")

    doc.save('/home/ga/Documents/inspection_report.docx')
    print("Document created successfully")

if __name__ == "__main__":
    create_inspection_report()
PYEOF

# Run the python script to generate the document
echo "Generating source document..."
python3 /tmp/create_source_doc.py
rm /tmp/create_source_doc.py

# Ensure ownership
chown ga:ga /home/ga/Documents/inspection_report.docx

# Clean up any previous run artifacts
rm -f /home/ga/Documents/inspection_report_formatted.docx 2>/dev/null || true

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/inspection_report.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer to appear
wait_for_window "LibreOffice Writer" 60 || wait_for_window "inspection_report" 30

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Dismiss "Tip of the Day" if it appears
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="