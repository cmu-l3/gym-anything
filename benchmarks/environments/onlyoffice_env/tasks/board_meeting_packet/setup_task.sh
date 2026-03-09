#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Meeting Packet Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/BoardMeeting"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create raw meeting notes file
cat > "$WORKSPACE_DIR/meeting_notes_raw.txt" << 'EOF'
Sept 20 board meeting notes:

People there: Maria Chen (chair), John Davis (treasurer), Sarah Kim, Michael Torres, Linda Washington
Not there: Robert Lee (sent regrets - traveling)

Maria called meeting to order 6:05 pm

John gave treasurer report - see his email for numbers

Discussed need for new freezer - current one making weird noise. Michael said he got quote from Restaurant Supply Warehouse for $1,200. Board agreed to approve purchase if current freezer dies. Vote was 4-0 (Maria, John, Sarah, Michael yes; Linda abstained because she just joined board)

Sarah reported on volunteer recruitment - we have 15 regular volunteers now, up from 11 last quarter. Still need more people for weekend shifts.

Maria said the lease renewal is coming up in March. Landlord hasn't raised rent in 2 years so expecting increase. John will reach out to landlord in January to negotiate.

Under new business: Linda proposed holiday food drive partnership with local high school. Board agreed this is good idea. Linda will coordinate with school principal.

Next meeting scheduled for December 15 at 6pm.

Meeting adjourned 7:20 pm
EOF

chown ga:ga "$WORKSPACE_DIR/meeting_notes_raw.txt"

# Create treasurer report (ugly format)
cat > "$WORKSPACE_DIR/treasurer_report.txt" << 'EOF'
Hey everyone, here's the financial update for Q4. Sorry it's not in a nice format, I'm not great with spreadsheets!

INCOME
Q3: $12,450
Q4: $15,200

EXPENSES - Food purchases
Q3: $8,100  
Q4: $9,350

EXPENSES - Rent
Q3: $2,400
Q4: $2,400

EXPENSES - Utilities
Q3: $650
Q4: $720

EXPENSES - Insurance
Q3: $480
Q4: $480

EXPENSES - Other
Q3: $320
Q4: $290

So we're in good shape. Let me know if you have questions.
- John
EOF

chown ga:ga "$WORKSPACE_DIR/treasurer_report.txt"

# Create action items file
cat > "$WORKSPACE_DIR/action_items_raw.txt" << 'EOF'
Action item updates:

From Michael: Freezer quote - COMPLETED. Got quote from Restaurant Supply Warehouse, sent to board via email.

From Sarah: Volunteer recruitment campaign - IN PROGRESS. Posted flyers at library and community college. Have 3 new inquiries this week. Target completion Feb 1.

From John: Landlord negotiation for lease - NOT STARTED. Will reach out in January as discussed. Due March 1 before lease expires March 31.

From Linda: Holiday food drive coordination - IN PROGRESS. Met with high school principal Nov 10. School will collect donations Dec 5-16. Pick up Dec 17. 

From Maria: Board liability insurance review - COMPLETED. Renewed policy with same provider, premium unchanged at $1,920/year.

From Sarah: Weekend volunteer schedule gaps - NOT STARTED. Need to create rotating schedule by Jan 15.
EOF

chown ga:ga "$WORKSPACE_DIR/action_items_raw.txt"

# Create agenda topics
cat > "$WORKSPACE_DIR/agenda_topics.txt" << 'EOF'
Call to order
Approval of September meeting minutes
Treasurer's report
Old business: Freezer purchase decision, Lease renewal status update, Holiday food drive results
New business: Weekend volunteer scheduling, Grant opportunities for 2025
Executive session (if needed)
Adjournment
EOF

chown ga:ga "$WORKSPACE_DIR/agenda_topics.txt"

echo "✅ Source files created in: $WORKSPACE_DIR"
echo "  - meeting_notes_raw.txt"
echo "  - treasurer_report.txt"
echo "  - action_items_raw.txt"
echo "  - agenda_topics.txt"

# Launch ONLYOFFICE with new blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new-document > /tmp/onlyoffice_board_packet_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_board_packet_task.log || true
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

echo "=== Board Meeting Packet Task Setup Complete ==="
echo ""
echo "📝 TASK: Create a professional board meeting packet"
echo ""
echo "📂 Source files available in: $WORKSPACE_DIR"
echo "   - meeting_notes_raw.txt (raw meeting notes)"
echo "   - treasurer_report.txt (financial data)"
echo "   - action_items_raw.txt (action item updates)"
echo "   - agenda_topics.txt (agenda items)"
echo ""
echo "📄 Create file: December_Board_Packet.docx in $WORKSPACE_DIR"
echo ""
echo "Required sections (in order):"
echo "  1. Cover Page (all text centered):"
echo "     - Organization: Riverside Community Food Pantry"
echo "     - Title: Board Meeting Packet"
echo "     - Date: December 15, 2024"
echo "     - Time: 6:00 PM"
echo "     - Location: Community Center, Room 3B"
echo ""
echo "  2. AGENDA (bold 14pt header, numbered list from agenda_topics.txt)"
echo ""
echo "  3. MINUTES - September 20, 2024 (bold 14pt header)"
echo "     - Format meeting_notes_raw.txt into proper minutes"
echo "     - Include Present/Absent sections"
echo "     - Bullet points for discussions"
echo ""
echo "  4. TREASURER'S REPORT - Q4 2024 (bold 14pt header)"
echo "     - Create table with columns: Category, Q3 Actual, Q4 Actual, Change"
echo "     - Include data from treasurer_report.txt"
echo "     - Calculate Change column (Q4 - Q3)"
echo "     - Add Total row at bottom"
echo ""
echo "  5. ACTION ITEMS UPDATE (bold 14pt header)"
echo "     - Create table with columns: Item, Owner, Status, Due Date"
echo "     - Extract info from action_items_raw.txt"
echo "     - Sort by status (Completed first, then In Progress, then Not Started)"
echo ""
echo "💾 Save as: $WORKSPACE_DIR/December_Board_Packet.docx"
echo ""
echo "⏱️  Estimated time: 15 minutes"