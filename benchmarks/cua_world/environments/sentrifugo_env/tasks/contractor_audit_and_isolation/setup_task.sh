#!/bin/bash
echo "=== Setting up contractor_audit_and_isolation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

wait_for_http "$SENTRIFUGO_URL" 60

echo "Cleaning up any prior run artifacts..."
# Delete any existing target employees or the target department
docker exec -i sentrifugo-db mysql -u root -prootpass123 sentrifugo << 'EOF'
DELETE FROM main_users WHERE employeeId IN ('EMP031','EMP032','EMP033','EMP034','EMP035','EMP036','EMP037','EMP038');
DELETE FROM main_employees_summary WHERE employeeId IN ('EMP031','EMP032','EMP033','EMP034','EMP035','EMP036','EMP037','EMP038');
DELETE FROM main_departments WHERE deptname='External Contractors';
EOF

echo "Injecting target contractors into standard departments..."
# We insert them with standard starting departments (e.g. 2=Finance, 3=Engineering)
cat > /tmp/insert_contractors.sql << 'EOF'
INSERT INTO main_users (id, employeeId, firstname, lastname, userfullname, emailaddress, emppassword, role_id, department_id, jobtitle_id, isactive, userstatus, reqtype) VALUES
(1031, 'EMP031', 'Alex', 'Vance', 'Alex Vance', 'alex.vance@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 2, 1, 1, 'old', 'Hire'),
(1032, 'EMP032', 'Priya', 'Kapoor', 'Priya Kapoor', 'priya.kapoor@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 3, 1, 1, 'old', 'Hire'),
(1033, 'EMP033', 'Marcus', 'Johnson', 'Marcus Johnson', 'marcus.johnson@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 2, 1, 1, 'old', 'Hire'),
(1034, 'EMP034', 'Elena', 'Rodriguez', 'Elena Rodriguez', 'elena.rodriguez@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 3, 1, 1, 'old', 'Hire'),
(1035, 'EMP035', 'David', 'Kim', 'David Kim', 'david.kim@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 2, 1, 1, 'old', 'Hire'),
(1036, 'EMP036', 'Sarah', 'OConnor', 'Sarah OConnor', 'sarah.oconnor@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 3, 1, 1, 'old', 'Hire'),
(1037, 'EMP037', 'James', 'Wilson', 'James Wilson', 'james.wilson@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 2, 1, 1, 'old', 'Hire'),
(1038, 'EMP038', 'Wei', 'Chen', 'Wei Chen', 'wei.chen@contractor.local', '5f4dcc3b5aa765d61d8327deb882cf99', 3, 3, 1, 1, 'old', 'Hire');

INSERT INTO main_employees_summary (user_id, employeeId, firstname, lastname, emailaddress, department_id, isactive) VALUES
(1031, 'EMP031', 'Alex', 'Vance', 'alex.vance@contractor.local', 2, 1),
(1032, 'EMP032', 'Priya', 'Kapoor', 'priya.kapoor@contractor.local', 3, 1),
(1033, 'EMP033', 'Marcus', 'Johnson', 'marcus.johnson@contractor.local', 2, 1),
(1034, 'EMP034', 'Elena', 'Rodriguez', 'elena.rodriguez@contractor.local', 3, 1),
(1035, 'EMP035', 'David', 'Kim', 'david.kim@contractor.local', 2, 1),
(1036, 'EMP036', 'Sarah', 'OConnor', 'sarah.oconnor@contractor.local', 3, 1),
(1037, 'EMP037', 'James', 'Wilson', 'james.wilson@contractor.local', 2, 1),
(1038, 'EMP038', 'Wei', 'Chen', 'wei.chen@contractor.local', 3, 1);
EOF
docker exec -i sentrifugo-db mysql -u root -prootpass123 sentrifugo < /tmp/insert_contractors.sql
rm /tmp/insert_contractors.sql

echo "Creating the contractor roster CSV on Desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/contractor_roster.csv << 'CSV'
EmployeeID,FirstName,LastName,Vendor,ContractStartDate,ContractEndDate
EMP031,Alex,Vance,TechStaffing Inc,2025-02-15,2026-02-15
EMP032,Priya,Kapoor,GlobalIT Solutions,2025-02-28,2026-02-28
EMP033,Marcus,Johnson,TechStaffing Inc,2025-06-01,2026-12-31
EMP034,Elena,Rodriguez,CodeCrafters LLC,2025-03-01,2026-03-01
EMP035,David,Kim,GlobalIT Solutions,2025-08-15,2026-08-15
EMP036,Sarah,OConnor,CodeCrafters LLC,2025-09-01,2026-09-01
EMP037,James,Wilson,TechStaffing Inc,2024-12-31,2025-12-31
EMP038,Wei,Chen,GlobalIT Solutions,2026-01-15,2027-01-15
CSV
chown ga:ga /home/ga/Desktop/contractor_roster.csv

# Ensure Sentrifugo is logged in and navigated to the Employees list to speed up agent start
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/index.php/employee/employeelist"
sleep 3

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="