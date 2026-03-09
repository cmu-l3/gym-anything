#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Neighborhood Petition Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document for the petition
DOC_PATH="$WORKSPACE_DIR/traffic_safety_petition.docx"

cat > /tmp/create_petition_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document for the user to fill in
doc = Document()

# Add a single blank paragraph to start with
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank petition document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_petition_doc.py
python3 /tmp/create_petition_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_petition_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_petition_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Neighborhood Petition Task Setup Complete ==="
echo "📝 Task: Create a petition for traffic safety on residential streets"
echo ""
echo "Required elements:"
echo "  1. Title: 'PETITION FOR TRAFFIC SAFETY' (bold, centered, large)"
echo "  2. Addressee: 'To: [Your City] City Council'"
echo "  3. Problem Statement: Describe speeding cars endangering children"
echo "  4. Proposed Solution: Request speed bump or stop sign installation"
echo "  5. Justification: 2-3 reasons supporting the request"
echo "  6. Signature Section: At least 10 signature lines"
echo "     Format: Name ________ Address ________ Date ________ Signature ________"
echo ""
echo "Save the document as 'traffic_safety_petition.docx' (Ctrl+S)"