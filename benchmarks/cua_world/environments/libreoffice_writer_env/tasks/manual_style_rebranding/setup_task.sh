#!/bin/bash
set -e

echo "=== Setting up Manual Style Rebranding Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate the messy source document using python-docx
# We inject manual formatting (Direct Formatting) that the agent must clear
cat << 'PYEOF' | python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set default style to Courier New (Legacy look)
style = doc.styles['Normal']
font = style.font
font.name = 'Courier New'
font.size = Pt(10)

# Heading 1 setup (Legacy look: Times New Roman)
h1 = doc.styles['Heading 1']
h1.font.name = 'Times New Roman'
h1.font.size = Pt(14)
h1.font.color.rgb = RGBColor(0, 0, 0)

# Title
doc.add_heading('OmniBase Database Server 4.0', 0)

# Section 1
doc.add_heading('Introduction', level=1)
p = doc.add_paragraph('OmniBase is a distributed, sharded database system designed for high availability.')
# Manual override: make this paragraph Arial (Direct Formatting)
for run in p.runs:
    run.font.name = 'Arial'

p = doc.add_paragraph('This manual covers installation, configuration, and maintenance procedures.')

# Warning 1
p = doc.add_paragraph('WARNING: Database corruption may occur if the write-ahead log is disabled during high load.')
# Manually bold the warning (Agent should replace with WarningText style)
p.runs[0].bold = True

# Section 2
doc.add_heading('Installation', level=1)
doc.add_paragraph('To install OmniBase, run the installer script located in the root directory.')

# Warning 2
p = doc.add_paragraph('WARNING: Do not unplug the server while the installer is partitioning drives.')
p.runs[0].bold = True
p.runs[0].font.color.rgb = RGBColor(255, 0, 0) # Manual red

# Section 3
doc.add_heading('Configuration', level=1)
p = doc.add_paragraph('Edit the omnibase.conf file to set your replication factor.')
# Manual override
for run in p.runs:
    run.font.size = Pt(12) 

# Warning 3
p = doc.add_paragraph('WARNING: API tokens are revoked after 24 hours if not refreshed.')
p.runs[0].italic = True

doc.add_heading('Troubleshooting', level=1)
doc.add_paragraph('If the service fails to start, check /var/log/omnibase.log.')

doc.save('/home/ga/Documents/omnibase_manual.docx')
print("Generated legacy manual at /home/ga/Documents/omnibase_manual.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/omnibase_manual.docx

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/omnibase_manual.docx > /dev/null 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "omnibase_manual" 30

# Maximize
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
    # Open Styles sidebar (F11) to help the agent
    safe_xdotool ga :1 key F11
fi

# Initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="