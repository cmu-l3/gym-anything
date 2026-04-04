#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up batch_import_customers task ==="

# 1. Ensure Manager.io is running and accessible
ensure_manager_running

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Create the source data file (TSV format)
# We use printf to ensure tabs are correctly inserted
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/new_leads.tsv << 'EOF'
Name	BillingAddress	Email
Bon app'	12, rue des Bouchers, Marseille 13008, France	sales@bonapp.fr
Bottom-Dollar Markets	23 Tsawassen Blvd., Tsawassen BC T2F 8M4, Canada	accounting@bottomdollar.ca
Cactus Comidas para llevar	Cerrito 333, Buenos Aires 1010, Argentina	info@cactuscomidas.ar
Die Wandernde Kuh	Adenauerallee 900, Stuttgart 70563, Germany	orders@wanderndekuh.de
EOF
chown ga:ga /home/ga/Documents/new_leads.tsv
chmod 644 /home/ga/Documents/new_leads.tsv

# 4. Record Initial State (Customer Count)
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# Login to get cookies
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key for Northwind
BIZ_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
# Extract key looking for the link to Northwind
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]*Northwind Traders' | awk -F'"' '{print $1}' | head -1)
if [ -z "$BIZ_KEY" ]; then
    # Fallback if specific name match fails
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]*' | head -1)
fi
echo "$BIZ_KEY" > /tmp/biz_key.txt

# Get initial customer count
# We count row elements or estimate based on table rows
CUST_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L)
# Simple count of table rows containing customer links (approximate but sufficient for delta check)
INITIAL_COUNT=$(echo "$CUST_PAGE" | grep -o 'view-customer' | wc -l || echo 0)
echo "$INITIAL_COUNT" > /tmp/initial_customer_count.txt

echo "Initial customer count recorded: $INITIAL_COUNT"

# 5. Open Manager.io at Customers page to save navigation time, or Summary
# Task description says "Navigate to Customers", so let's start at Summary to be safe
open_manager_at "summary"

# 6. Open a file browser or just ensure the file is visible?
# We'll just leave the file there. The agent knows how to find it.

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="