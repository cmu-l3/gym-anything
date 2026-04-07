#!/bin/bash
set -e
echo "=== Setting up Upload and Duplicate Evidence task ==="

source /workspace/scripts/task_utils.sh

# 1. Install dependencies for data generation
echo "Installing python dependencies..."
pip3 install pandas openpyxl >/dev/null 2>&1 || true

# 2. Generate the Evidence File (Real Data)
echo "Generating evidence file..."
mkdir -p /home/ga/Documents
cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

# Generate realistic access logs
num_records = 150
start_date = datetime(2025, 1, 1, 8, 0, 0)
employees = [
    ("E001", "Smith, John"), ("E002", "Doe, Jane"), ("E003", "Rivera, Carlos"),
    ("E004", "Chen, Wei"), ("E005", "Johnson, Sarah"), ("E006", "Admin, System")
]
doors = ["Front Entrance", "Server Room", "Rear Exit", "Loading Dock", "Executive Suite"]
statuses = ["Granted", "Granted", "Granted", "Denied", "Granted"]

data = []
for _ in range(num_records):
    dt = start_date + timedelta(days=random.randint(0, 30), minutes=random.randint(0, 1440))
    emp = random.choice(employees)
    door = random.choice(doors)
    status = random.choice(statuses)
    
    # Add some suspicious activity for "Internal Audit" context
    if emp[0] == "E003" and door == "Server Room" and dt.hour > 20:
        status = "Denied"
    
    data.append({
        "Timestamp": dt.strftime("%Y-%m-%d %H:%M:%S"),
        "Badge ID": emp[0],
        "Employee Name": emp[1],
        "Access Point": door,
        "Status": status
    })

df = pd.DataFrame(data)
df.to_excel("/home/ga/Documents/Access_Logs_2025.xlsx", index=False)
print("Evidence file generated.")
EOF
python3 /tmp/generate_data.py
chown ga:ga /home/ga/Documents/Access_Logs_2025.xlsx
chmod 644 /home/ga/Documents/Access_Logs_2025.xlsx

# 3. Create the Case via API
echo "Creating Complaint Case..."
ensure_portforward
wait_for_arkcase

CASE_TITLE="Internal Audit - Unauthorized Access"
CASE_DETAILS="Investigation into after-hours server room access attempts. Suspected badge cloning or misuse. Evidence logs need to be analyzed."

RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"High\",
    \"status\": \"ACTIVE\"
}")

CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null || echo "")
echo "Created Case ID: $CASE_ID"
echo "$CASE_ID" > /tmp/task_case_id.txt

# 4. Prepare Browser
echo "Preparing Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 4
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Log in and navigate to the case (or at least the complaints list)
if [ -n "$CASE_ID" ]; then
    TARGET_URL="https://localhost:9443/arkcase/#!/complaint/${CASE_ID}"
else
    TARGET_URL="https://localhost:9443/arkcase/#!/complaints"
fi

# Launch Firefox first, then login
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
sleep 10
auto_login_arkcase "$TARGET_URL"

# 5. Finalize Setup
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Case Created: $CASE_TITLE ($CASE_ID)"
echo "Evidence File: /home/ga/Documents/Access_Logs_2025.xlsx"

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
