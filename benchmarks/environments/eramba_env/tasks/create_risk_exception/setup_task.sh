#!/bin/bash
set -e
echo "=== Setting up create_risk_exception task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure Eramba is up and running
# (The base environment setup does this, but we double check)
echo "Checking Eramba status..."
if ! curl -s http://localhost:8080 > /dev/null; then
    echo "Waiting for Eramba to be responsive..."
    sleep 10
fi

# 2. Record initial count of risk exceptions
echo "Recording initial database state..."
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risk_exceptions WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_exception_count.txt
echo "Initial risk exceptions count: $INITIAL_COUNT"

# 3. Ensure the target Risk exists ("Phishing Attacks on Employees")
# This is usually seeded by setup_eramba.sh, but we verify it here.
RISK_EXISTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE title LIKE '%Phishing Attacks%' AND deleted=0;" 2>/dev/null || echo "0")

if [ "$RISK_EXISTS" -eq "0" ]; then
    echo "Seeding missing risk requirement..."
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO risks (title, description, risk_score, created, modified) VALUES ('Phishing Attacks on Employees', 'Risk of credential theft via social engineering.', 5, NOW(), NOW());"
fi

# 4. Prepare Firefox
echo "Starting Firefox..."
ensure_firefox_eramba "http://localhost:8080/risk-management/risk-exceptions/index"

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 5 # Wait for page load
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="