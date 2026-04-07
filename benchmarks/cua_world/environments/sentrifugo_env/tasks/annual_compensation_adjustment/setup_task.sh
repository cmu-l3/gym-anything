#!/bin/bash
echo "=== Setting up annual_compensation_adjustment task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# Clean up previous state to ensure a clean slate
# Deletes any existing salary and allowance records for the target users
UIDS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT id FROM main_users WHERE employeeId IN ('EMP002', 'EMP006', 'EMP011', 'EMP014', 'EMP018');" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

if [ -n "$UIDS" ]; then
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "DELETE FROM main_employeesalary WHERE user_id IN ($UIDS);" 2>/dev/null || true
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "DELETE FROM main_employeeallowances WHERE user_id IN ($UIDS);" 2>/dev/null || true
    
    # Insert placeholder default salaries to match the prompt's initial state
    for uid in $(echo $UIDS | tr ',' ' '); do
        docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "INSERT INTO main_employeesalary (user_id, amount, currency_id, salarytype_id) VALUES ($uid, '80000', 1, 1);" 2>/dev/null || true
    done
fi

# Create the confidential memo document on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q1_2026_comp_review.txt << 'EOF'
═══════════════════════════════════════════════════════════════
         CONFIDENTIAL — Q1 2026 COMPENSATION REVIEW
         Approved by: VP of Human Resources
         Effective Date: March 1, 2026
═══════════════════════════════════════════════════════════════

INSTRUCTIONS FOR HR ADMIN:
Please update the Sentrifugo Salary records for the following 
engineering staff. Set currency to USD. Enter values as Annual amounts.
Add the bonus as a new Allowance named "Performance Bonus".

1. Sarah Johnson (EMP002)
   - New Base Salary: 115000
   - Performance Bonus Allowance: 10500

2. Jessica Liu (EMP006)
   - New Base Salary: 132500
   - Performance Bonus Allowance: 14000

3. Daniel Wilson (EMP011)
   - New Base Salary: 98400
   - Performance Bonus Allowance: 7200

4. Thomas Moore (EMP014)
   - ** HOLD - PENDING TERMINATION - DO NOT PROCESS **
   - Base: 105000 / Bonus: 5000

5. Nicole Anderson (EMP018)
   - New Base Salary: 145000
   - Performance Bonus Allowance: 18500
EOF

chown ga:ga /home/ga/Desktop/q1_2026_comp_review.txt

# Navigate to Sentrifugo employee list
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 3

# Maximize Firefox for the agent's convenience
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture the initial starting state showing the setup succeeded
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="