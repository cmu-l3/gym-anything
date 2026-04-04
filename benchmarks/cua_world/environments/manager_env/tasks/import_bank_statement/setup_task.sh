#!/bin/bash
# Setup script for import_bank_statement task
# Creates a CSV bank statement and sets up Manager.io

set -e
echo "=== Setting up import_bank_statement task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the CSV bank statement file
# Note: Format is Date,Description,Amount
# Dates are in DD/MM/YYYY format which Manager often defaults to, or standard ISO
# We'll use DD/MM/YYYY to match common defaults, or YYYY-MM-DD.
# Manager is smart with dates, but let's be standard.
mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/bank_statement_january.csv"

cat > "$CSV_FILE" << EOF
Date,Description,Amount
05/01/2024,"Payment received - Alfreds Futterkiste INV-001",2500.00
08/01/2024,"Transfer to Exotic Liquids - PO-2024-001",-1800.00
12/01/2024,"Office rent payment - January 2024",-1200.00
15/01/2024,"Utility bill - City Power & Light",-350.00
18/01/2024,"Payment received - Ernst Handel INV-002",4200.00
22/01/2024,"Office supplies - Staples order",-275.50
25/01/2024,"Payment received - Alfreds Futterkiste INV-003",1850.00
30/01/2024,"Bank service charges",-45.00
EOF

chown ga:ga "$CSV_FILE"
echo "Created CSV file at $CSV_FILE"

# 2. Ensure Manager is running and accessible
wait_for_manager 60

# 3. Record initial state (Transaction count in Cash on Hand)
# We need to find the Key for "Cash on Hand" to query it specifically, 
# or just scrape the bank accounts summary page.
# For setup, we'll just record the start time.
date +%s > /tmp/task_start_time.txt

# 4. Open Manager at the Bank Accounts page to save the agent some clicks
# and ensure a consistent starting state.
echo "Opening Manager.io at Bank Accounts..."
open_manager_at "bank_accounts"

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 5 # Wait for Firefox to settle
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="