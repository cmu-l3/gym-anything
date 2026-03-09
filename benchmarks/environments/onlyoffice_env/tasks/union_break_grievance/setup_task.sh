#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Union Break Grievance Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the rough notes file (messy, realistic)
cat > "$WORKSPACE_DIR/break_notes.txt" << 'EOF'
MEAL BREAK VIOLATIONS - MY NOTES

Mon 1/15 - tried to take break at 11:30, Curtis came over at 11:45 saying they need me back, only got 15 mins!! Everyone was there, tons of witnesses

wed 1/17 same thing happened!! 11:30-11:50, only 20 minutes, Curtis again, so frustrating

Fri 1/19 - scheduled 2pm break, got called back at 2:22, only 22 minutes this is ridiculous

1/22 monday - 11:30 break again only til 11:48, 18 minutes, this is BS, I had lunch in the microwave still

Thurs 1/25 afternoon break 2pm-2:25 Curtis said "floor is backed up" only 25 min, I was still eating!

My break is supposed to be 30 MINUTES this is in the contract Article 12!!
I'm losing money and not getting proper rest.
Need to file grievance ASAP.
EOF

# Create contract snippet
cat > "$WORKSPACE_DIR/contract_snippet.txt" << 'EOF'
TEAMSTERS LOCAL 455 COLLECTIVE BARGAINING AGREEMENT
Effective: January 1, 2024 - December 31, 2026

Article 12: Meal and Rest Periods

Section 4: Meal Breaks
Any employee working a shift of six (6) hours or more shall receive one (1) uninterrupted meal period of thirty (30) minutes. The meal period shall be unpaid but must be free from all work duties and supervisory interruption.

In the event that an employee's meal break is interrupted or shortened due to operational needs, management requests, or any other reason, the employee shall receive penalty pay of one and one-half (1.5) hours at their regular hourly rate for each occurrence.

Section 5: Enforcement
Violations of meal break provisions shall be subject to the grievance procedure outlined in Article 18. The Union steward must be notified within five (5) business days of any violation.
EOF

# Create shift roster
cat > "$WORKSPACE_DIR/shift_roster.txt" << 'EOF'
NORTHWEST FULFILLMENT CENTER - SHIFT ROSTER
January 2024 - Warehouse Floor A

Monday, January 15, 2024 - Morning Shift (7:00 AM - 3:30 PM):
- Jamal Washington (Employee #4521)
- Marcus Reed (Employee #4502)
- Lisa Chen (Employee #4389)
- DeShawn Porter (Employee #4612)
- Jennifer Martinez (Employee #4455)

Wednesday, January 17, 2024 - Morning Shift (7:00 AM - 3:30 PM):
- Jamal Washington (Employee #4521)
- Marcus Reed (Employee #4502)
- Lisa Chen (Employee #4389)
- Jennifer Martinez (Employee #4455)
- Tyler Brooks (Employee #4567)

Friday, January 19, 2024 - Afternoon Shift (2:00 PM - 10:30 PM):
- Jamal Washington (Employee #4521)
- Tyler Brooks (Employee #4567)
- Sarah Kim (Employee #4423)
- Marcus Reed (Employee #4502)
- DeShawn Porter (Employee #4612)

Monday, January 22, 2024 - Morning Shift (7:00 AM - 3:30 PM):
- Jamal Washington (Employee #4521)
- Lisa Chen (Employee #4389)
- DeShawn Porter (Employee #4612)
- Jennifer Martinez (Employee #4455)
- Sarah Kim (Employee #4423)

Thursday, January 25, 2024 - Afternoon Shift (2:00 PM - 10:30 PM):
- Jamal Washington (Employee #4521)
- Tyler Brooks (Employee #4567)
- Sarah Kim (Employee #4423)
- DeShawn Porter (Employee #4612)
- Marcus Reed (Employee #4502)

Supervisor: Curtis Williams (Employee #3201)
EOF

# Set ownership
chown ga:ga "$WORKSPACE_DIR"/*.txt

echo "✅ Source documents created:"
echo "   - break_notes.txt (rough notes)"
echo "   - contract_snippet.txt (union contract excerpt)"
echo "   - shift_roster.txt (witness roster)"

# Launch ONLYOFFICE Document Editor
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors > /tmp/onlyoffice_grievance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_grievance_task.log || true
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

echo "=== Union Break Grievance Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You are Jamal Washington, a warehouse associate filing a union grievance"
echo "for repeated meal break violations over the past 3 weeks."
echo ""
echo "📂 SOURCE DOCUMENTS (review these first):"
echo "   - ~/Documents/break_notes.txt - Your informal notes"
echo "   - ~/Documents/contract_snippet.txt - Union contract excerpt"
echo "   - ~/Documents/shift_roster.txt - Coworker roster"
echo ""
echo "📝 CREATE: ~/Documents/grievance_meal_breaks.docx"
echo ""
echo "REQUIRED CONTENT:"
echo "  1. Header: Grievance #GRV-2024-0847, Jamal Washington #4521"
echo "  2. Subject: Formal Grievance - Meal Break Violations"
echo "  3. Contract Reference: Article 12, Section 4"
echo "  4. Opening statement describing violations"
echo "  5. Table with 5 incidents (Date | Break Time | Duration | Time Lost | Witness)"
echo "  6. Financial calculation: 5 violations × 1.5 hrs × \$22.50/hr"
echo "  7. Closing statement with remedy request"
echo "  8. Use bold for headers, table borders, 300+ words"
echo ""
echo "💾 Save as: ~/Documents/grievance_meal_breaks.docx (Ctrl+S)"