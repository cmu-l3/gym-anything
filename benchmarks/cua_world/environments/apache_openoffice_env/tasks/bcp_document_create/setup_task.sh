#!/bin/bash
# Setup script for bcp_document_create task
# Provides company info JSON for agent reference; clears output location

echo "=== Setting up BCP Document Create Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Meridian_BCP_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/company_info.json 2>/dev/null || true

# Copy company info reference data
cp /workspace/tasks/bcp_document_create/assets/company_info.json \
   /home/ga/Documents/company_info.json
chown ga:ga /home/ga/Documents/company_info.json

echo "0" > /tmp/initial_bcp_file_exists
date +%s > /tmp/task_start_timestamp
ls -la /home/ga/Documents/ > /tmp/initial_dir_state 2>&1 || true

# Ensure desktop shortcut
SOFFICE_BIN="/opt/openoffice4/program/soffice"
if [ -x "$SOFFICE_BIN" ]; then
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
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== BCP Document Create Setup Complete ==="
echo "Company info: /home/ga/Documents/company_info.json"
echo "Expected output: /home/ga/Documents/Meridian_BCP_2024.odt"
