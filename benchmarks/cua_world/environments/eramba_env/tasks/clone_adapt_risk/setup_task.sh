#!/bin/bash
set -e
echo "=== Setting up clone_adapt_risk task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Eramba is running and database is ready
# (Handled by env hooks, but good to verify)

# 2. Ensure Source Risk exists ("Phishing Attacks on Employees")
# We use SQL to insert it if missing to ensure a clean starting state
echo "Checking for source risk..."
SOURCE_RISK_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM risks WHERE title='Phishing Attacks on Employees' AND deleted=0;")

if [ "$SOURCE_RISK_COUNT" -eq "0" ]; then
    echo "Creating source risk..."
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO risks (title, threats, vulnerabilities, description, risk_mitigation_strategy_id, risk_score, created, modified) \
         VALUES ('Phishing Attacks on Employees', 'Social engineering, email-based attacks', \
         'Lack of user security awareness', \
         'Employees may be targeted by phishing emails leading to credential theft.', \
         3, 5.0, NOW(), NOW());"
fi

# 3. Ensure Target Risk does NOT exist (Clean slate)
echo "Cleaning up any previous target risk..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "UPDATE risks SET deleted=1, modified=NOW() WHERE title='Phishing Attacks on Remote Contractors';"

# 4. Capture Source Risk details for later verification (to prove cloning)
echo "Capturing source risk details..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT threats, vulnerabilities FROM risks WHERE title='Phishing Attacks on Employees' AND deleted=0 LIMIT 1;" > /tmp/source_risk_details.txt

# 5. Launch Firefox and navigate to Risk Management
# The URL for Risk Management > Risks is typically /risks/index
ensure_firefox_eramba "http://localhost:8080/risks/index"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="