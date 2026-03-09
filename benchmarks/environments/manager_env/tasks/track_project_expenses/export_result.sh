#!/bin/bash
echo "=== Exporting Track Project Expenses Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Helper to get the business key (UUID) for Northwind Traders
get_business_key() {
    curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt -L "http://localhost:8080/businesses" | \
    grep -oP 'start\?Key=\K[^"]*' | head -1
}

# Login to get cookies
curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt -X POST "http://localhost:8080/login" -d "Username=administrator" -L > /dev/null

# Get Business Key
BIZ_KEY=$(get_business_key)
if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business key"
    BIZ_KEY="unknown"
fi
echo "Business Key: $BIZ_KEY"

# ---------------------------------------------------------
# 1. Check if Projects Module is Enabled
# ---------------------------------------------------------
PROJECTS_PAGE=$(curl -s -b /tmp/cookies.txt "http://localhost:8080/projects?Key=$BIZ_KEY")
PROJECTS_MODULE_ENABLED="false"
# If the module is enabled, the page should contain "New Project" button or list
if echo "$PROJECTS_PAGE" | grep -q "New Project"; then
    PROJECTS_MODULE_ENABLED="true"
fi

# ---------------------------------------------------------
# 2. Extract Project Data (Name and Total Expenses)
# ---------------------------------------------------------
# Scrape the table row for "Website Revamp"
# Format in HTML table usually has the name and then columns for Income, Expenses, Profit
# We look for the row containing "Website Revamp" and extract the number in the Expenses column (often negative or positive depending on view)
# Simple check: does the page contain "Website Revamp" and "750.00"?
PROJECT_EXISTS="false"
PROJECT_TOTAL_MATCH="false"

if [ "$PROJECTS_MODULE_ENABLED" = "true" ]; then
    if echo "$PROJECTS_PAGE" | grep -q "Website Revamp"; then
        PROJECT_EXISTS="true"
        # Check for 750.00 near Website Revamp or in the page generally if specific parsing is hard in bash
        # Manager usually formats numbers like "750.00"
        if echo "$PROJECTS_PAGE" | grep -q "750.00"; then
            PROJECT_TOTAL_MATCH="true"
        fi
    fi
fi

# ---------------------------------------------------------
# 3. Check Chart of Accounts for "IT Services"
# ---------------------------------------------------------
COA_PAGE=$(curl -s -b /tmp/cookies.txt "http://localhost:8080/chart-of-accounts?Key=$BIZ_KEY")
ACCOUNT_EXISTS="false"
if echo "$COA_PAGE" | grep -q "IT Services"; then
    ACCOUNT_EXISTS="true"
fi

# ---------------------------------------------------------
# 4. Check Payments
# ---------------------------------------------------------
PAYMENTS_PAGE=$(curl -s -b /tmp/cookies.txt "http://localhost:8080/payments?Key=$BIZ_KEY")
PAYMENT1_FOUND="false"
PAYMENT2_FOUND="false"

# Check Payment 1: TechHost Inc, 150.00
if echo "$PAYMENTS_PAGE" | grep -q "TechHost Inc" && echo "$PAYMENTS_PAGE" | grep -q "150.00"; then
    PAYMENT1_FOUND="true"
fi

# Check Payment 2: Freelance Dev, 600.00
if echo "$PAYMENTS_PAGE" | grep -q "Freelance Dev" && echo "$PAYMENTS_PAGE" | grep -q "600.00"; then
    PAYMENT2_FOUND="true"
fi

# ---------------------------------------------------------
# 5. Capture Final Screenshot
# ---------------------------------------------------------
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------
# 6. Create JSON Result
# ---------------------------------------------------------
# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "projects_module_enabled": $PROJECTS_MODULE_ENABLED,
    "project_exists": $PROJECT_EXISTS,
    "project_total_match": $PROJECT_TOTAL_MATCH,
    "account_exists": $ACCOUNT_EXISTS,
    "payment1_found": $PAYMENT1_FOUND,
    "payment2_found": $PAYMENT2_FOUND
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json