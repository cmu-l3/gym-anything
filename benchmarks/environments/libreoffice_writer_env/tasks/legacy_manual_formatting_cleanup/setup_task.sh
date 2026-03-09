#!/bin/bash
set -e
echo "=== Setting up Legacy Manual Formatting Cleanup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Generate the "Legacy" document with manual formatting
# We use python-docx to create a file with direct formatting (bad practice)
# that the agent must fix.
echo "Generating legacy document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, RGBColor
from docx.oxml.ns import qn

doc = Document()

# Helper to apply direct formatting
def add_manual_heading1(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Arial Black'
    run.font.size = Pt(18)
    # Force font name for compatibility
    r = run._element
    r.rPr.rFonts.set(qn('w:eastAsia'), 'Arial Black')

def add_manual_heading2(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Arial'
    run.font.size = Pt(14)
    run.bold = True

def add_body_text(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(12)

def add_code_line(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Courier New'
    run.font.size = Pt(10)

def add_warning(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Arial'
    run.font.color.rgb = RGBColor(255, 0, 0) # Red
    run.bold = True

# --- CONTENT GENERATION ---

add_manual_heading1("System Requirements")
add_body_text("Before installing the server software, ensure your environment meets the following criteria:")

add_manual_heading2("Hardware Specifications")
add_body_text("The server requires a minimum of 4 CPU cores and 16GB of RAM. Storage throughput should be at least 300 MB/s.")

add_warning("CRITICAL: Do not attempt installation on single-core virtual machines.")

add_manual_heading2("Software Dependencies")
add_body_text("You must have the following packages installed:")
add_code_line("sudo apt-get update")
add_code_line("sudo apt-get install nginx python3-pip postgresql")

add_manual_heading1("Installation Steps")

add_manual_heading2("Database Configuration")
add_body_text("Initialize the database cluster using the following command:")
add_code_line("initdb -D /var/lib/postgres/data")
add_warning("WARNING: This will wipe existing data in the target directory.")

add_manual_heading2("Firewall Settings")
add_body_text("Open ports 80 and 443 for web traffic.")
add_code_line("ufw allow 80/tcp")
add_code_line("ufw allow 443/tcp")

add_manual_heading1("Troubleshooting")

add_manual_heading2("User Permissions")
add_body_text("If you encounter permission denied errors, check the owner of the config file:")
add_code_line("ls -l /etc/server/config.json")
add_body_text("The owner should be 'www-data'.")

add_warning("NOTE: Never run the server process as root user.")

doc.save("/home/ga/Documents/legacy_install_guide.docx")
print("Legacy document generated successfully.")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/legacy_install_guide.docx
chmod 666 /home/ga/Documents/legacy_install_guide.docx

# Ensure LibreOffice is not running
pkill soffice || true

# Start LibreOffice Writer with the file
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/legacy_install_guide.docx &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "legacy_install_guide" 60

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# Dismiss any initial dialogs (Tip of the Day, etc.)
sleep 5
safe_xdotool ga :1 key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="