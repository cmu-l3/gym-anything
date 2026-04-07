#!/bin/bash
echo "=== Setting up four_day_workweek_policy_update task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time.txt

# Reset Leaves to standard 5-day workweek norms
sentrifugo_db_root_query "UPDATE main_employeeleavetypes SET numberofdays=20 WHERE leavetype='Annual Leave';" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_employeeleavetypes SET numberofdays=10 WHERE leavetype='Sick Leave';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_employeeleavetypes WHERE leavetype='Wellness Day';" 2>/dev/null || true

# Reset Shifts (trying common table names for robustness)
for table in main_shifts main_workingshifts main_workshifts; do
    sentrifugo_db_root_query "UPDATE $table SET starttime='09:00:00', endtime='17:00:00' WHERE shiftname='General Shift';" 2>/dev/null || true
done

# Reset Weekends (if table exists)
for table in main_weekends main_workingdays; do
    sentrifugo_db_root_query "UPDATE $table SET isactive=0 WHERE day='Friday';" 2>/dev/null || true
done

# Drop corporate memo on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/4_day_workweek_memo.txt << 'MEMO'
ACME GLOBAL TECHNOLOGIES
Board of Directors Directive: 4-Day Workweek Transition
Effective Date: Immediate
=========================================================

To all HR Administrators,

As part of our commitment to employee well-being, we are transitioning to a 4-day workweek. Please update the HRMS configuration immediately to reflect the following changes:

1. WEEKEND CONFIGURATION
   - Add Friday as an official non-working weekend day (alongside Saturday and Sunday).

2. SHIFT MANAGEMENT
   - Update the existing "General Shift".
   - New Start Time: 08:00
   - New End Time: 18:00
   (This establishes our new 10-hour workday structure).

3. LEAVE ENTITLEMENT PRORATION
   - Edit "Annual Leave": Reduce allowance from 20 days to 16 days.
   - Edit "Sick Leave": Reduce allowance from 10 days to 8 days.

4. NEW WELLNESS BENEFIT
   - Create a new leave type.
   - Name: Wellness Day
   - Code: WD
   - Number of Days: 2

Please ensure all changes are saved and active in the system.
=========================================================
MEMO

chown ga:ga /home/ga/Desktop/4_day_workweek_memo.txt

# Log in the agent and navigate to the dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="