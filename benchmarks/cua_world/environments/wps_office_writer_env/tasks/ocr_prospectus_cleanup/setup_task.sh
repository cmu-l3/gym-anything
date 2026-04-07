#!/bin/bash
echo "=== Setting up OCR Prospectus Cleanup Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the documents directory
su - ga -c "mkdir -p /home/ga/Documents"

# Generate the messy DOCX file using python
su - ga -c "python3 - << 'EOF'
import textwrap
try:
    from docx import Document
    from docx.shared import Pt
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'python-docx'])
    from docx import Document
    from docx.shared import Pt

doc = Document()

# Add unstyled headings
doc.add_paragraph('PROSPECTUS SUMMARY')
doc.add_paragraph('The Company')

text1 = \"The Company was incorporated in 1994 and opened its virtual doors on the World Wide Web in July 1995. We offer our customers a vast selection of books, CDs, DVDs, and other products, convenience, and discounted prices. We believe we are the leading online retailer of books. Our strategy is to offer the most comprehensive selection of products, maintain a low-cost structure, and provide excellent customer service.\"

text2 = \"We have experienced significant growth in our sales and operations. In 1996, our first full year of operations, our net sales were $15.7 million. We expect to incur significant operating losses for the foreseeable future, due to the heavy investment required to build our brand, expand our product offerings, and develop our technology infrastructure. We intend to aggressively invest in marketing and promotion to drive customer acquisition.\"

text3 = \"An investment in our common stock involves a high degree of risk. You should carefully consider the risks and uncertainties described below before making an investment decision. We have a limited operating history, which makes it difficult to evaluate our business and prospects. We have accumulated a deficit of $9.0 million as of December 31, 1996, and we expect to incur substantial additional losses. If we fail to successfully execute our business model, our business will suffer.\"

def add_messy_paragraphs(doc, text):
    lines = textwrap.wrap(text, width=65)
    for line in lines:
        doc.add_paragraph(line)
    doc.add_paragraph('') # Empty paragraph for visual double spacing

add_messy_paragraphs(doc, text1)
add_messy_paragraphs(doc, text2)

doc.add_paragraph('Risk Factors')
add_messy_paragraphs(doc, text3)

doc.add_paragraph('Selected Financial Data')
doc.add_paragraph('Year Ended December 31,')
# Space-aligned fake table
doc.add_paragraph('Item    1995    1996    1997')
doc.add_paragraph('Net sales    $511    $15,746    $147,787')
doc.add_paragraph('Cost of sales    $409    $12,287    $118,969')
doc.add_paragraph('Gross profit    $102    $3,459    $28,818')
doc.add_paragraph('Operating expenses    $410    $6,438    $58,459')
doc.add_paragraph('Loss from operations    $(308)    $(2,979)    $(29,641)')

doc.save('/home/ga/Documents/project_pegasus_raw.docx')
EOF"

# Start WPS Writer
if ! pgrep -f "wps" > /dev/null; then
    echo "Starting WPS Writer..."
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/project_pegasus_raw.docx &"
    sleep 5
fi

# Wait and maximize
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Re-focus just in case
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="