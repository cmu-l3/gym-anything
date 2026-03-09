#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Update Weekly Ops Deck Task ==="

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Desktop

# Define variables for randomization
NEW_DATE="October 23, 2024"
THROUGHPUT_VAL=$((RANDOM % 50 + 800)) # 800-850
DEFECT_RATE_VAL="0.$((RANDOM % 9 + 1))%" # 0.1% - 0.9%

# Save expected values for verification (hidden from agent)
cat > /tmp/expected_values.json << EOF
{
    "date": "$NEW_DATE",
    "throughput": "$THROUGHPUT_VAL",
    "defect_rate": "$DEFECT_RATE_VAL",
    "removed_person": "Sarah"
}
EOF

# Create the data file for the agent
cat > /home/ga/Desktop/Week_43_Data.txt << EOF
WEEKLY OPS DATA - WEEK 43
=========================

Date: $NEW_DATE

Metrics Update:
- Throughput: $THROUGHPUT_VAL units
- Defect Rate: $DEFECT_RATE_VAL

Status Updates:
- Project "Migration" is now resolved (Green).

Staffing:
- Sarah has returned from leave.
EOF
chown ga:ga /home/ga/Desktop/Week_43_Data.txt

# Generate the initial ODP file programmatically using python-pptx or odfpy
# We use odfpy here since it's native to the environment/LibreOffice
python3 << PYEOF
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties, TableProperties, TableColumnProperties, TableRowProperties, TableCellProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox, CustomShape, EnhancedGeometry
from odf.table import Table, TableColumn, TableRow, TableCell

def create_style(doc, name, family, parent=None, **properties):
    style = Style(name=name, family=family, parent_stylename=parent)
    for prop_type, prop_attr in properties.items():
        if prop_type == 'text':
            style.addElement(TextProperties(**prop_attr))
        elif prop_type == 'paragraph':
            style.addElement(ParagraphProperties(**prop_attr))
        elif prop_type == 'graphic':
            style.addElement(GraphicProperties(**prop_attr))
    doc.styles.addElement(style)
    return style

doc = OpenDocumentPresentation()

# SLIDE 1: Title
page1 = Page(name="Slide1")
doc.presentation.addElement(page1)

# Title Frame
frame_t1 = Frame(width="24cm", height="3cm", x="2cm", y="4cm")
page1.addElement(frame_t1)
tb_t1 = TextBox()
frame_t1.addElement(tb_t1)
tb_t1.addElement(P(text="Weekly Ops Review"))

# Subtitle Frame (Date to change)
frame_s1 = Frame(width="24cm", height="2cm", x="2cm", y="8cm")
page1.addElement(frame_s1)
tb_s1 = TextBox()
frame_s1.addElement(tb_s1)
tb_s1.addElement(P(text="Week 42 - October 16, 2024"))

# SLIDE 2: Metrics Table
page2 = Page(name="Slide2")
doc.presentation.addElement(page2)

# Title
frame_t2 = Frame(width="24cm", height="2cm", x="2cm", y="1cm")
page2.addElement(frame_t2)
tb_t2 = TextBox()
frame_t2.addElement(tb_t2)
tb_t2.addElement(P(text="Production Metrics"))

# Table
frame_table = Frame(width="20cm", height="10cm", x="4cm", y="4cm")
page2.addElement(frame_table)
table = Table(name="MetricsTable")
frame_table.addElement(table)

table.addElement(TableColumn()) # Metric
table.addElement(TableColumn()) # Week 41
table.addElement(TableColumn()) # Week 42 (Target for update)

# Header Row
tr_h = TableRow()
table.addElement(tr_h)
for header in ["Metric", "Week 41", "Week 42"]:
    tc = TableCell()
    tc.addElement(P(text=header))
    tr_h.addElement(tc)

# Row 1: Throughput
tr_1 = TableRow()
table.addElement(tr_1)
tc_1a = TableCell()
tc_1a.addElement(P(text="Throughput"))
tr_1.addElement(tc_1a)
tc_1b = TableCell()
tc_1b.addElement(P(text="750"))
tr_1.addElement(tc_1b)
tc_1c = TableCell()
tc_1c.addElement(P(text="780")) # Needs update
tr_1.addElement(tc_1c)

# Row 2: Defect Rate
tr_2 = TableRow()
table.addElement(tr_2)
tc_2a = TableCell()
tc_2a.addElement(P(text="Defect Rate"))
tr_2.addElement(tc_2a)
tc_2b = TableCell()
tc_2b.addElement(P(text="1.2%"))
tr_2.addElement(tc_2b)
tc_2c = TableCell()
tc_2c.addElement(P(text="1.1%")) # Needs update
tr_2.addElement(tc_2c)


# SLIDE 3: Status
page3 = Page(name="Slide3")
doc.presentation.addElement(page3)
frame_t3 = Frame(width="24cm", height="2cm", x="2cm", y="1cm")
page3.addElement(frame_t3)
tb_t3 = TextBox()
frame_t3.addElement(tb_t3)
tb_t3.addElement(P(text="Project Status"))

# Project Label
frame_lbl = Frame(width="10cm", height="2cm", x="2cm", y="5cm")
page3.addElement(frame_lbl)
tb_lbl = TextBox()
frame_lbl.addElement(tb_lbl)
tb_lbl.addElement(P(text="Migration Project:"))

# Status Shape (Red Circle)
# Define style for red fill
red_style = Style(name="RedFill", family="graphic")
red_style.addElement(GraphicProperties(fill="solid", fill_color="#ff0000"))
doc.automaticstyles.addElement(red_style)

# Create ellipse
circle = CustomShape(name="MigrationStatus", width="3cm", height="3cm", x="12cm", y="4.5cm", stylename="RedFill")
circle.addElement(P(text="Delayed"))
circle.addElement(EnhancedGeometry(type="ellipse"))
page3.addElement(circle)


# SLIDE 4: Staffing
page4 = Page(name="Slide4")
doc.presentation.addElement(page4)
frame_t4 = Frame(width="24cm", height="2cm", x="2cm", y="1cm")
page4.addElement(frame_t4)
tb_t4 = TextBox()
frame_t4.addElement(tb_t4)
tb_t4.addElement(P(text="Team Availability"))

# List
frame_list = Frame(width="20cm", height="10cm", x="2cm", y="4cm")
page4.addElement(frame_list)
tb_list = TextBox()
frame_list.addElement(tb_list)
tb_list.addElement(P(text="On Shift: All Operators"))
tb_list.addElement(P(text=""))
tb_list.addElement(P(text="On Leave:"))
tb_list.addElement(P(text="- John"))
tb_list.addElement(P(text="- Sarah")) # Needs removal
tb_list.addElement(P(text="- Mike"))

doc.save("/home/ga/Documents/Presentations/Ops_Review_Week_42.odp")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/Presentations/Ops_Review_Week_42.odp

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch LibreOffice
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/Ops_Review_Week_42.odp > /tmp/impress.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 60

# Maximize window
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="