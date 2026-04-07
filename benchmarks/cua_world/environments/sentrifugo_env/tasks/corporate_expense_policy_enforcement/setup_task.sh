#!/bin/bash
echo "=== Setting up Corporate Expense Policy Enforcement task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_timestamp

# 2. Generate the real-world austerity memo
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q3_austerity_memo.txt << 'MEMO'
MEMORANDUM
TO: Finance & HR Administration
FROM: Chief Financial Officer
DATE: August 15, 2026
SUBJECT: Q3 Expense Policy Update - Immediate Austerity Measures

To manage our Q3 burn rate effectively, the executive team has approved the following immediate changes to our corporate reimbursement policy:

1. The "Client Entertainment" expense limit is reduced to $100.00 per claim. (Please update the category description/limit to reflect this).
2. The "Telecom & Internet" reimbursement category is fully discontinued (please deactivate this category in the HRMS).

ACTION REQUIRED:
Please update the system configurations to reflect these rules immediately. 
Furthermore, please review all currently pending expense claims in the system queue for David Kim (EMP005). 
Apply these new rules retroactively:
- Claim 1: Client Entertainment ($85.00)
- Claim 2: Client Entertainment ($120.00)
- Claim 3: Telecom & Internet ($45.00)

Claims violating the new limits or using discontinued categories must be Rejected. Valid claims within the new limits should be Approved so payroll can process them.
MEMO

chown ga:ga /home/ga/Desktop/q3_austerity_memo.txt
chmod 644 /home/ga/Desktop/q3_austerity_memo.txt

# 3. Attempt to inject baseline categories into the database
# We use best-effort injection. If the schema differs slightly, the agent can still complete it via UI.
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "
CREATE TABLE IF NOT EXISTS main_expensecategories (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    categoryname VARCHAR(255), 
    description VARCHAR(255), 
    isactive INT DEFAULT 1
);
" 2>/dev/null || true

# Insert/Update Telecom & Internet (Active)
if ! docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT id FROM main_expensecategories WHERE categoryname='Telecom & Internet'" | grep -q "[0-9]"; then
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "INSERT INTO main_expensecategories (categoryname, description, isactive) VALUES ('Telecom & Internet', 'Monthly phone and internet', 1);" 2>/dev/null || true
else
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "UPDATE main_expensecategories SET isactive=1 WHERE categoryname='Telecom & Internet';" 2>/dev/null || true
fi

# Insert/Update Client Entertainment (Limit 150)
if ! docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT id FROM main_expensecategories WHERE categoryname='Client Entertainment'" | grep -q "[0-9]"; then
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "INSERT INTO main_expensecategories (categoryname, description, isactive) VALUES ('Client Entertainment', 'Limit: $150.00', 1);" 2>/dev/null || true
else
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "UPDATE main_expensecategories SET description='Limit: $150.00', isactive=1 WHERE categoryname='Client Entertainment';" 2>/dev/null || true
fi

# 4. Open Firefox to Sentrifugo
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="