#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tenant Maintenance Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a minimal blank document with correct filename
DOC_PATH="$WORKSPACE_DIR/Maintenance_Log_Unit2B.docx"

cat > /tmp/create_blank_maintenance_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document
doc = Document()

# Add a single empty paragraph to ensure it's a valid document
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank maintenance log document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_maintenance_doc.py
python3 /tmp/create_blank_maintenance_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_maintenance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_maintenance_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Tenant Maintenance Log Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add title: 'Apartment Maintenance Request Log'"
echo "  2. Add subtitle: 'Unit 2B - 145 Oak Street'"
echo "  3. Create a table with 6 columns:"
echo "     • Date Reported"
echo "     • Issue Description"
echo "     • Priority"
echo "     • Contact Method"
echo "     • Landlord Response"
echo "     • Status"
echo "  4. Format headers as bold"
echo "  5. Add at least 5 maintenance request entries with:"
echo "     • Dates (e.g., 2024-09-15, 10/03/2024)"
echo "     • Detailed issue descriptions"
echo "     • Priority levels (Low/Medium/High/Urgent)"
echo "     • Contact methods (Email/Text/Phone/In-person)"
echo "     • Landlord responses"
echo "     • Status (Pending/In Progress/Resolved/Ignored)"
echo "  6. Add a 'Notes' section below the table"
echo "  7. Save the document (Ctrl+S)"