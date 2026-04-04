#!/bin/bash
set -e

echo "=== Setting up User Manual Sections Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the draft document using python-docx
# This creates a "messy" draft: flat structure, manual bolding instead of styles, wrong font
python3 << 'PYEOF'
import os
try:
    from docx import Document
    from docx.shared import Pt, Inches
    from docx.enum.text import WD_ALIGN_PARAGRAPH
except ImportError:
    print("Installing python-docx...")
    os.system("pip install python-docx")
    from docx import Document
    from docx.shared import Pt, Inches
    from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# --- Helper to add "messy" text ---
def add_messy_para(text, bold=False, size=10, align=None):
    p = doc.add_paragraph()
    run = p.add_run(text)
    # Wrong font and size for the task (Liberation Serif, 10pt)
    run.font.name = "Liberation Serif"
    run.font.size = Pt(size)
    run.bold = bold
    if align:
        p.alignment = align
    return p

# --- TITLE PAGE CONTENT (Should be Section 1) ---
for _ in range(4): doc.add_paragraph("")
add_messy_para("AquaTrack Pro 3000", bold=True, size=24, align=WD_ALIGN_PARAGRAPH.CENTER)
add_messy_para("Water Quality Monitoring System", bold=True, size=16, align=WD_ALIGN_PARAGRAPH.CENTER)
add_messy_para("User Manual", bold=False, size=14, align=WD_ALIGN_PARAGRAPH.CENTER)
for _ in range(8): doc.add_paragraph("")
add_messy_para("Version 3.2.1", align=WD_ALIGN_PARAGRAPH.CENTER)
add_messy_para("March 2024", align=WD_ALIGN_PARAGRAPH.CENTER)
add_messy_para("Cascade Environmental Technologies, Inc.", align=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_page_break()

# --- CHAPTER 1: INTRODUCTION ---
add_messy_para("Introduction", bold=True, size=14) # Should be Heading 1
add_messy_para("Product Overview", bold=True, size=11) # Should be Heading 2
add_messy_para(
    "The AquaTrack Pro 3000 is a multiparameter water quality sonde designed for long-term "
    "deployment in fresh, estuarine, and marine environments. It features a titanium "
    "housing, antifouling wiper, and four sensor ports compatible with pH, conductivity, "
    "dissolved oxygen, and turbidity probes."
)
add_messy_para("Intended Use", bold=True, size=11)
add_messy_para(
    "This device is intended for environmental monitoring, aquaculture management, and "
    "regulatory compliance reporting in accordance with EPA Method 150.1. It is not "
    "rated for use in explosive atmospheres or industrial chemical processing tanks."
)

# --- CHAPTER 2: INSTALLATION ---
add_messy_para("Installation Guide", bold=True, size=14)
add_messy_para("System Requirements", bold=True, size=11)
add_messy_para(
    "The data logger software requires Windows 10 or later, 8GB RAM, and a dedicated "
    "USB 3.0 port. Bluetooth 5.0 capability is recommended for wireless field calibration."
)
add_messy_para("Hardware Setup", bold=True, size=11)
add_messy_para(
    "1. Remove the protective bulkhead cap.\n"
    "2. Lubricate the O-rings with the supplied silicone grease.\n"
    "3. Insert sensors into ports A through D, ensuring alignment pins match.\n"
    "4. Hand-tighten the retaining nuts. Do not use tools."
)

# --- CHAPTER 3: OPERATION ---
add_messy_para("Operation", bold=True, size=14)
add_messy_para("Sensor Calibration", bold=True, size=11)
add_messy_para(
    "Calibration should be performed before every deployment. Rinse sensors with "
    "deionized water. Immerse in standard buffer solutions (pH 4, 7, 10) and wait "
    "for readings to stabilize before accepting values."
)
add_messy_para("Data Logging", bold=True, size=11)
add_messy_para(
    "To start a logging session, navigate to the 'Deploy' menu. Select logging interval "
    "(default: 15 minutes). Ensure internal battery voltage is above 12.5V."
)

# --- CHAPTER 4: TROUBLESHOOTING ---
add_messy_para("Troubleshooting", bold=True, size=14)
add_messy_para("Error Codes", bold=True, size=11)
add_messy_para(
    "E01: Battery Low. Replace 4x AA alkaline batteries.\n"
    "E04: Wiper Jam. Inspect brush for debris.\n"
    "E12: Sensor Drift. Clean sensor face and recalibrate."
)
add_messy_para("Contacting Support", bold=True, size=11)
add_messy_para(
    "For technical assistance, contact support@cascadetech.com or call 1-800-555-0199. "
    "Please have your device serial number ready."
)

doc.save("/home/ga/Documents/aquatrack_manual_draft.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/aquatrack_manual_draft.docx
chmod 666 /home/ga/Documents/aquatrack_manual_draft.docx

# Compute MD5 of original to ensure agent doesn't just overwrite it with a new blank file
md5sum /home/ga/Documents/aquatrack_manual_draft.docx | cut -d' ' -f1 > /tmp/original_md5.txt

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/aquatrack_manual_draft.docx > /tmp/writer.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "LibreOffice Writer"; then
            echo "Writer window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "LibreOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure focus
DISPLAY=:1 wmctrl -a "LibreOffice Writer" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="