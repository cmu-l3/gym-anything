#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Genealogy Source Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Ensure proper ownership
chown -R ga:ga "$WORKSPACE_DIR"

echo "✅ Workspace directory ready: $WORKSPACE_DIR"

# Launch ONLYOFFICE Writer with a new blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:word > /tmp/onlyoffice_genealogy_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_genealogy_task.log || true
    # Don't exit - may still start
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - may still appear
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Genealogy Source Log Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Add document title: 'Genealogy Research Source Log'"
echo "  2. Add subtitle with context (e.g., 'Johnson Family Research - 2024')"
echo "  3. Insert a table with 4 columns:"
echo "     - Source ID"
echo "     - Source Citation"
echo "     - Repository/Location"
echo "     - Notes"
echo "  4. Add at least 3 diverse source entries, such as:"
echo "     - Census record (e.g., 1940 U.S. Federal Census)"
echo "     - Vital record (e.g., birth certificate, death certificate)"
echo "     - Online database (e.g., FamilySearch, Ancestry)"
echo "  5. Apply italic formatting to publication/collection titles in citations"
echo "  6. Add a 'Research Notes' section after the table"
echo "  7. Add bullet points with next research steps or questions"
echo "  8. Save as: /home/ga/Documents/TextDocuments/genealogy_source_log.docx"
echo ""
echo "Expected output path: /home/ga/Documents/TextDocuments/genealogy_source_log.docx"