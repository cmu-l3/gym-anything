#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Business Letter Task ==="

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Documents/results

# Clean up any existing files
rm -f /home/ga/Documents/partnership_letter.odt 2>/dev/null || true
rm -f /home/ga/Documents/partnership_letter.doc 2>/dev/null || true
rm -f /home/ga/Documents/partnership_letter.docx 2>/dev/null || true

# Copy real business data reference for the agent (if needed)
if [ -f "/workspace/assets/business_data.json" ]; then
    cp /workspace/assets/business_data.json /home/ga/Documents/
    chown ga:ga /home/ga/Documents/business_data.json
    echo "Copied real business data reference to Documents folder"
fi

# Record initial state (no file should exist)
echo "0" > /tmp/initial_file_exists
ls -la /home/ga/Documents/ > /tmp/initial_dir_state 2>&1 || true

# NOTE: We do NOT launch OpenOffice Writer here.
# The task description instructs the agent to "Open Apache OpenOffice Writer
# (double-click the desktop shortcut or launch from menu)" - this is part of the task.
# The agent must demonstrate the ability to launch the application.

# Ensure OpenOffice is available and executable
SOFFICE_BIN="/opt/openoffice4/program/soffice"
if [ -x "$SOFFICE_BIN" ]; then
    echo "OpenOffice Writer is installed at $SOFFICE_BIN"
else
    echo "WARNING: OpenOffice Writer not found at expected location"
fi

# Ensure the desktop shortcut exists for the agent to use
DESKTOP_FILE="/usr/share/applications/openoffice4-writer.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    echo "Desktop entry exists: $DESKTOP_FILE"
    # Copy to user's desktop for easy access
    cp "$DESKTOP_FILE" /home/ga/Desktop/ 2>/dev/null || true
    chown ga:ga /home/ga/Desktop/*.desktop 2>/dev/null || true
    chmod +x /home/ga/Desktop/*.desktop 2>/dev/null || true
else
    # Create desktop shortcut if it doesn't exist
    mkdir -p /home/ga/Desktop
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
    echo "Created desktop shortcut for OpenOffice Writer"
fi

# Take initial screenshot showing the desktop (before agent action)
take_screenshot /tmp/task_initial.png

echo "=== Create Business Letter Task Setup Complete ==="
echo ""
echo "TASK: Create a formal business letter"
echo ""
echo "The agent must:"
echo "  1. Open Apache OpenOffice Writer (from desktop shortcut or menu)"
echo "  2. Create a new business letter with:"
echo "     - Sender: Red Hat, Inc., 100 East Davie Street, Raleigh, NC 27601"
echo "     - Date: February 3, 2026"
echo "     - Recipient: Mr. Arvind Krishna, Chairman and CEO, IBM Corporation"
echo "     - Address: 1 New Orchard Road, Armonk, NY 10504"
echo "     - Salutation: Dear Mr. Krishna,"
echo "     - Body: Open source collaboration initiative (at least 3 sentences)"
echo "     - Closing: Respectfully,"
echo "     - Signature: Matt Hicks, President and CEO, Red Hat, Inc."
echo "  3. Save as /home/ga/Documents/partnership_letter.odt"
echo ""
echo "Initial state: Desktop with OpenOffice Writer NOT running"
