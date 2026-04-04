#!/bin/bash
echo "=== Setting up Add Insurance Carrier Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for LibreHealth to be ready
wait_for_librehealth 60

# 2. Clean State: Remove "Cigna Health Spring" if it already exists (idempotency)
echo "Cleaning up any existing records for 'Cigna Health Spring'..."
librehealth_query "DELETE FROM insurance_companies WHERE name LIKE 'Cigna Health Spring%'"

# 3. Create the input file on the Desktop
INFO_FILE="/home/ga/Desktop/new_carrier_info.txt"
cat > "$INFO_FILE" << EOF
New Insurance Carrier Request
-----------------------------
Please add the following insurance company to the system immediately.

Company Name: Cigna Health Spring
Address: 500 Great Circle Road
City: Nashville
State: TN
Zip Code: 37228

Phone: (800) 668-3813
Payer ID (CMS ID): 62308
EOF

chown ga:ga "$INFO_FILE"
chmod 644 "$INFO_FILE"
echo "Created info file at $INFO_FILE"

# 4. Record Initial State (Anti-Gaming)
# Count existing insurance companies
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM insurance_companies")
echo "$INITIAL_COUNT" > /tmp/lh_initial_insurance_count
echo "Initial insurance company count: $INITIAL_COUNT"

# Record start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox at Login Page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="