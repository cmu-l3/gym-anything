#!/bin/bash
set -e
echo "=== Setting up Technical Manual Master Compile Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/chapters
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous artifacts
rm -f /home/ga/Documents/AeroTurbine_Master.odm 2>/dev/null || true
rm -rf /home/ga/Documents/chapters/* 2>/dev/null || true

# Generate Chapter files using Python and odfpy (pre-installed in env)
# We generate real ODT files so the agent has valid targets to link.
echo "Generating chapter files..."
sudo -u ga python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import H, P

chapters = [
    ("01_introduction.odt", "Chapter 1: Introduction", 
     "The AeroTurbine 500-X is a high-bypass turbofan engine designed for regional jets. This manual covers basic operation parameters."),
    ("02_safety_protocols.odt", "Chapter 2: Safety Protocols", 
     "WARNING: Maintain a 15-foot safety zone around the intake during operation. Hearing protection is mandatory in the test cell."),
    ("03_operation_procedures.odt", "Chapter 3: Operation Procedures", 
     "1. Engage Master Switch.\n2. Verify APU status.\n3. Rotate N1 to 20% before introducing fuel."),
    ("04_maintenance_schedule.odt", "Chapter 4: Maintenance Schedule", 
     "A-Check: Every 500 flight hours.\nB-Check: Every 2000 flight hours. inspect fan blades for FOD damage."),
    ("05_troubleshooting.odt", "Chapter 5: Troubleshooting", 
     "Error 404: EGT Sensor Fault.\nError 503: Oil Pressure Low.\nConsult engineering if vibration exceeds limits.")
]

base_dir = "/home/ga/Documents/chapters"

for filename, title, content in chapters:
    doc = OpenDocumentText()
    
    # Add a Heading 1 style (standard for TOC generation)
    h1style = Style(name="Heading 1", family="paragraph")
    h1style.addElement(TextProperties(attributes={'fontsize':"24pt", 'fontweight':"bold"}))
    doc.styles.addElement(h1style)
    
    # Add Content
    h = H(outlinelevel=1, stylename=h1style, text=title)
    doc.text.addElement(h)
    
    for line in content.split('\n'):
        p = P(text=line)
        doc.text.addElement(p)
        
    output_path = os.path.join(base_dir, filename)
    doc.save(output_path)
    print(f"Created {output_path}")

PYEOF

# Ensure OpenOffice is ready (but not open, let agent open it)
# We just verify it's installed
if [ ! -x "/opt/openoffice4/program/soffice" ]; then
    echo "WARNING: OpenOffice binary not found!"
fi

# Create a desktop shortcut for convenience
cat > /home/ga/Desktop/OpenOffice-Writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
chown ga:ga /home/ga/Desktop/OpenOffice-Writer.desktop
chmod +x /home/ga/Desktop/OpenOffice-Writer.desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="