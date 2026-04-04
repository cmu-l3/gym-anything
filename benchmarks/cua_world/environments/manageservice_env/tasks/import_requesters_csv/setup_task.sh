#!/bin/bash
set -e
echo "=== Setting up import_requesters_csv task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt
date +%s%3N > /tmp/task_start_time_ms.txt

source /workspace/scripts/task_utils.sh

# Wait for SDP to be ready
ensure_sdp_running

# 1. Create the CSV file with "messy" headers
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/nebula_acq_users.csv << 'CSVEOF'
GivenName,Surname,EmailAddress,JobPosition,DepartmentCode,Mobile
Elena,Corves,elena.corves@nebula-logistics.test,Logistics Coordinator,Nebula_Ops,555-0101
Marcus,Thorne,marcus.thorne@nebula-logistics.test,Fleet Manager,Nebula_Ops,555-0102
Sarah,Jennings,sarah.jennings@nebula-logistics.test,Dispatcher,Nebula_Ops,555-0103
David,Wu,david.wu@nebula-logistics.test,Warehouse Lead,Nebula_Warehouse,555-0104
Jessica,Perez,jessica.perez@nebula-logistics.test,Inventory Specialist,Nebula_Warehouse,555-0105
Robert,Langford,robert.langford@nebula-logistics.test,Forklift Operator,Nebula_Warehouse,555-0106
Amanda,Chen,amanda.chen@nebula-logistics.test,Procurement Analyst,Nebula_Finance,555-0107
Thomas,Hardy,thomas.hardy@nebula-logistics.test,Accounts Payable,Nebula_Finance,555-0108
Jennifer,Smalls,jennifer.smalls@nebula-logistics.test,HR Generalist,Nebula_Admin,555-0109
Michael,O'Connor,michael.oconnor@nebula-logistics.test,IT Support,Nebula_IT,555-0110
Linda,Wei,linda.wei@nebula-logistics.test,System Admin,Nebula_IT,555-0111
James,Burke,james.burke@nebula-logistics.test,Driver,Nebula_Fleet,555-0112
Patricia,Cane,patricia.cane@nebula-logistics.test,Driver,Nebula_Fleet,555-0113
Steven,Ross,steven.ross@nebula-logistics.test,Driver,Nebula_Fleet,555-0114
Elizabeth,Yuan,elizabeth.yuan@nebula-logistics.test,Operations Manager,Nebula_Ops,555-0115
CSVEOF

chown ga:ga /home/ga/Documents/nebula_acq_users.csv

# 2. Record initial user count for verification
INITIAL_USER_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM aaauser;" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_USER_COUNT"

# 3. Clean up any previous attempts (delete users with nebula emails if they exist)
# This ensures a clean state if the task is restarted without container reset
sdp_db_exec "DELETE FROM aaauser WHERE first_name IN ('Elena', 'Marcus') AND last_name IN ('Corves', 'Thorne');" 2>/dev/null || true

# 4. Open Firefox to SDP Login
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Take initial screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="