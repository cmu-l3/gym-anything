#!/bin/bash
set -e

echo "=== Setting up Compliance Traceability Matrix Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Directories
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$DOCS_DIR"

# Clean previous runs
rm -f "$DOCS_DIR/NeuroStim_SRS.odt"
rm -f "$DOCS_DIR/NeuroStim_SRS_v2.odt"
rm -f "$DOCS_DIR/trace_data.json"

# 1. Create trace_data.json
cat > "$DOCS_DIR/trace_data.json" << 'EOF'
[
  {
    "req_id": "REQ-SYS-01",
    "verification_id": "VP-055",
    "method": "Bench Test"
  },
  {
    "req_id": "REQ-SYS-02",
    "verification_id": "VP-056",
    "method": "Analysis"
  },
  {
    "req_id": "REQ-SYS-03",
    "verification_id": "VP-088",
    "method": "Field Test"
  },
  {
    "req_id": "REQ-SYS-04",
    "verification_id": "VP-012",
    "method": "Helium Leak Test"
  },
  {
    "req_id": "REQ-SYS-05",
    "verification_id": "VP-099",
    "method": "Safety Inspection"
  }
]
EOF
chown ga:ga "$DOCS_DIR/trace_data.json"

# 2. Create the initial ODT document programmatically
# We use python3 with odfpy to ensure valid ODT structure with Headings
echo "Generating NeuroStim_SRS.odt..."
cat > /tmp/gen_odt.py << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import H, P, Span

doc = OpenDocumentText()

# Create Heading 1 Style
h1style = Style(name="Heading 1", family="paragraph")
h1style.addElement(TextProperties(attributes={'fontsize':"24pt",'fontweight':"bold"}))
h1style.addElement(ParagraphProperties(attributes={'breakbefore':"page"})) # Just for emphasis
doc.styles.addElement(h1style)

# Title
doc.text.addElement(H(outlinelevel=1, stylename=h1style, text="NeuroStim X1 - System Requirements Specification"))
doc.text.addElement(P(text="Version 1.0 | Confidential"))
doc.text.addElement(P(text=""))

# Requirements
requirements = [
    ("REQ-SYS-01: Pulse Width Accuracy", "The system shall maintain pulse width accuracy within +/- 5% of the programmed value across the full operating temperature range."),
    ("REQ-SYS-02: Battery End-of-Life Indicator", "The system shall trigger an Elective Replacement Indicator (ERI) when battery impedance exceeds 5 kOhms."),
    ("REQ-SYS-03: Wireless Telemetry Range", "The system shall maintain bidirectional telemetry communication at a distance of up to 2 meters in an open air environment."),
    ("REQ-SYS-04: Hermetic Sealing Integrity", "The titanium can enclosure shall have a helium leak rate of less than 1.0 x 10^-9 std cc He/sec."),
    ("REQ-SYS-05: Emergency Stop Function", "The system shall immediately cease stimulation upon receipt of the encoded emergency stop command from the clinician programmer.")
]

for title, body in requirements:
    # Adding Heading with outline-level is crucial for Cross-Reference > Headings to work
    doc.text.addElement(H(outlinelevel=1, stylename=h1style, text=title))
    doc.text.addElement(P(text=body))
    # Add some filler
    doc.text.addElement(P(text="Rationale: Derived from clinical safety standards IEC 60601-1."))
    doc.text.addElement(P(text=""))

doc.save("/home/ga/Documents/NeuroStim_SRS.odt")
PYEOF

python3 /tmp/gen_odt.py
chown ga:ga "$DOCS_DIR/NeuroStim_SRS.odt"

# 3. Setup Desktop Shortcut (Helper)
if [ -x "/opt/openoffice4/program/soffice" ]; then
    mkdir -p /home/ga/Desktop
    cat > /home/ga/Desktop/OpenOffice-Writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Edit Text Documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/OpenOffice-Writer.desktop
    chmod +x /home/ga/Desktop/OpenOffice-Writer.desktop
fi

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
ls -l --time-style=+%s "$DOCS_DIR/NeuroStim_SRS.odt" | awk '{print $6}' > /tmp/initial_file_mtime.txt

# 5. Take Screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="