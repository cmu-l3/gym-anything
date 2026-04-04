#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Workplace Incident Documentation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw incident notes file
RAW_NOTES_PATH="$WORKSPACE_DIR/warehouse_incidents_raw.txt"

cat > "$RAW_NOTES_PATH" << 'RAWEOF'
NOTES - Safety Issues at Riverside Logistics Warehouse

3/15/24 - Forklift brake failure, nobody checked. Marcus almost hit the wall
5/2/24 - Emergency exit blocked by pallets again. I took a photo.
3/28/24 - Spill in aisle 7, no wet floor sign for 3+ hours. Jamie slipped.
4/10/24 - Fire extinguisher missing from zone C, reported to Tom, nothing done
5/20/24 - Forklift brake issue AGAIN, same vehicle, still not fixed
4/25/24 - Overhead light fell, missed Carlos by 2 feet, no inspection after
3/8/24 - Loading dock guardrail broken, reported, still not repaired
5/15/24 - No safety goggles available in chemical area, ordered 2 months ago
4/2/24 - Carbon monoxide detector beeping (low battery?) for 2 weeks straight

Witnesses: Jamie Torres, Carlos Mendez, Marcus Johnson, Sarah Kim
Supervisor notified: Tom Reynolds (on all dates via email or verbally)
Facility: Riverside Logistics, 450 Industrial Pkwy, Sacramento CA
RAWEOF

chown ga:ga "$RAW_NOTES_PATH"

echo "✅ Raw incident notes created at: $RAW_NOTES_PATH"

# Create an empty document to start with (agent will populate it)
# We launch ONLYOFFICE without a file, letting agent create new document
# OR we can create a minimal blank document

# Option: Create a minimal blank document
DOC_PATH="$WORKSPACE_DIR/OSHA_complaint_timeline.docx"

cat > /tmp/create_blank_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a completely blank document
doc = Document()

# Add a single empty paragraph to ensure it's a valid document
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_doc.py
python3 /tmp/create_blank_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank target document created at: $DOC_PATH"

# Launch ONLYOFFICE with the blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_incident_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_incident_task.log || true
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

echo "=== Workplace Incident Documentation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Maria, a warehouse worker, needs to create a formal OSHA complaint"
echo "documenting repeated safety violations at her workplace."
echo ""
echo "📝 YOUR TASK:"
echo "Read the scattered notes from: $RAW_NOTES_PATH"
echo "Create a professional complaint document at: $DOC_PATH"
echo ""
echo "📄 REQUIRED STRUCTURE:"
echo ""
echo "1. HEADER (centered, bold):"
echo "   - Title: 'WORKPLACE SAFETY VIOLATION REPORT'"
echo "   - Facility: Riverside Logistics, 450 Industrial Pkwy, Sacramento CA"
echo "   - Date range: March 8, 2024 - May 20, 2024"
echo ""
echo "2. EXECUTIVE SUMMARY:"
echo "   - Brief paragraph explaining the pattern"
echo "   - State: 9 documented violations over 74 days"
echo "   - Note: Supervisor (Tom Reynolds) was notified of all incidents"
echo "   - State: Violations remain uncorrected"
echo ""
echo "3. INCIDENT TIMELINE TABLE:"
echo "   Columns: Date | Violation Type | Description | Witness(es)"
echo "   - Sort incidents chronologically (March 8 → May 20)"
echo "   - Categorize violations appropriately:"
echo "     * Equipment Failure (forklift brakes)"
echo "     * Blocked Exits (pallets blocking exit)"
echo "     * Inadequate PPE (missing goggles)"
echo "     * Missing Safety Equipment (fire extinguisher)"
echo "     * Environmental Hazard (spill, CO detector)"
echo "     * Maintenance Neglect (guardrail, light)"
echo ""
echo "4. PATTERN ANALYSIS:"
echo "   - Total incidents: 9"
echo "   - Time span: 74 days (March 8 to May 20)"
echo "   - Average frequency: approximately 1 incident every 8 days"
echo "   - Repeat violations: 2 forklift brake incidents (3/15 and 5/20)"
echo ""
echo "💡 TIPS:"
echo "   - Section headers should be bold, 14pt"
echo "   - Body text: 11pt"
echo "   - Use proper table with borders"
echo "   - Professional appearance for regulatory submission"
echo "   - Save with Ctrl+S when complete"
echo ""