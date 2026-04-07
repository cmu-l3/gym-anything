#!/bin/bash
echo "=== Setting up company_spinoff_restructure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Sentrifugo to be ready
wait_for_http "$SENTRIFUGO_URL" 60

echo "Configuring database baseline state..."
# Force the exact initial state using an atomic SQL block
# This guarantees that the target employees are exactly where the manifest says they are,
# and cleans up any "Vendor Management" department from previous task runs.
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
-- Clean up previous run
DELETE FROM main_departments WHERE deptname='Vendor Management';

-- Ensure base departments are active
UPDATE main_departments SET isactive=1 WHERE deptname IN ('Sales', 'Marketing', 'Finance & Accounting');

-- Assign Sales employees (EMP005, EMP008, EMP019)
UPDATE main_users SET department_id=(SELECT id FROM main_departments WHERE deptname='Sales' LIMIT 1), isactive=1 WHERE employeeId IN ('EMP005', 'EMP008', 'EMP019');

-- Assign Marketing employees (EMP014, EMP018, EMP011)
UPDATE main_users SET department_id=(SELECT id FROM main_departments WHERE deptname='Marketing' LIMIT 1), isactive=1 WHERE employeeId IN ('EMP014', 'EMP018', 'EMP011');

-- Assign Control employee (EMP003 in Finance)
UPDATE main_users SET department_id=(SELECT id FROM main_departments WHERE deptname='Finance & Accounting' LIMIT 1), isactive=1 WHERE employeeId='EMP003';
"

echo "Creating spinoff manifest document..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/spinoff_manifest.txt << 'EOF'
ACME GLOBAL TECHNOLOGIES
Corporate Restructuring Directive — SPINOFF INITIATIVE
=====================================================
Due to the spinoff of our Sales and Marketing divisions into a separate entity, please execute the following system changes immediately:

PHASE 1: RETAIN KEY PERSONNEL
1. Create a new department named "Vendor Management".
2. We are retaining Matthew Garcia (EMP011) and Tyler Moore (EMP019) to manage the relationship with the new entity. Transfer them into the new "Vendor Management" department. Ensure their accounts remain ACTIVE.

PHASE 2: DEACTIVATE SPINOFF PERSONNEL
1. Deactivate ALL OTHER employees currently in the "Marketing" department. (Do not delete, only deactivate).
2. Deactivate ALL OTHER employees currently in the "Sales" department.

PHASE 3: DEACTIVATE DEPARTMENTS
1. Deactivate the "Marketing" department.
2. Deactivate the "Sales" department.

CRITICAL: Do NOT alter employees in any other departments (e.g., Finance, Engineering, Data Science).
=====================================================
EOF
chown ga:ga /home/ga/Desktop/spinoff_manifest.txt

echo "Preparing Firefox..."
# Ensure browser is logged in and ready
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 5

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="