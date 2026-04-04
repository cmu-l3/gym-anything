#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Court Exhibit List Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create instructions file for reference
INSTRUCTIONS_PATH="/home/ga/Documents/TextDocuments/exhibit_list_instructions.txt"

cat > "$INSTRUCTIONS_PATH" << 'INSTRUCTEOF'
COURT EXHIBIT LIST TASK
========================

CASE: SC-2025-04157
Sarah Mitchell (Plaintiff) v. Mike's Renovations LLC (Defendant)

YOUR TASK:
Create a formal exhibit list document following these specifications.

DOCUMENT STRUCTURE:
1. Header (centered, bold):
   - Line 1: IN THE SMALL CLAIMS COURT - CASE #SC-2025-04157
   - Line 2: Sarah Mitchell (Plaintiff) v. Mike's Renovations LLC (Defendant)
   - Line 3: PLAINTIFF'S EXHIBIT LIST

2. Create a 3-column table with headers:
   - Column 1: Exhibit Number
   - Column 2: Date
   - Column 3: Description

3. Enter these 8 exhibits IN CHRONOLOGICAL ORDER (by date):

   Exhibit A | 01/15/2025 | Written contract for bathroom renovation signed by both parties
   Exhibit B | 01/15/2025 | Invoice #1047 showing $3,500 deposit payment
   Exhibit C | 01/16/2025 | Bank statement showing check #2891 cleared for $3,500
   Exhibit D | 01/22/2025 | Text message from defendant stating work would begin January 24th
   Exhibit E | 01/30/2025 | Email from plaintiff requesting work status update
   Exhibit F | 02/03/2025 | Text message from defendant stating "family emergency, will return next week"
   Exhibit G | 02/18/2025 | Certified mail receipt showing demand letter sent to defendant
   Exhibit H | 02/20/2025 | Photos showing unfinished bathroom with exposed plumbing (3 photos)

4. Save the document as: Exhibit_List_SC-2025-04157.docx
   Location: /home/ga/Documents/TextDocuments/

FORMATTING TIPS:
- Use Insert > Table to create the table
- Make headers bold for professional appearance
- Ensure exhibits are listed in date order (earliest to latest)
- Use consistent date format (MM/DD/YYYY recommended)
- Keep descriptions clear and concise

VERIFICATION CRITERIA:
✓ Case number and title present
✓ 3-column table structure
✓ All 8 exhibits present (A through H)
✓ Chronological order maintained
✓ Accurate descriptions with key identifying information
✓ Saved with correct filename
INSTRUCTEOF

chown ga:ga "$INSTRUCTIONS_PATH"

echo "✅ Instructions created at: $INSTRUCTIONS_PATH"

# Launch ONLYOFFICE Document Editor with blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new document > /tmp/onlyoffice_court_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_court_task.log || true
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

# Give agent time to see the window
sleep 2

echo "=== Court Exhibit List Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "   Create a formal Small Claims Court exhibit list for Case #SC-2025-04157"
echo ""
echo "📝 REQUIREMENTS:"
echo "   1. Add case header with case number and parties"
echo "   2. Create 3-column table (Exhibit Number | Date | Description)"
echo "   3. Add 8 exhibits (A through H) in chronological order"
echo "   4. Save as: Exhibit_List_SC-2025-04157.docx"
echo ""
echo "📖 Full instructions available at: $INSTRUCTIONS_PATH"
echo ""
echo "⏱️  Recommended time: 5-8 minutes"
echo ""