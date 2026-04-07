#!/bin/bash
echo "=== Setting up Detect Rapid Data Destruction task ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_DIR="/var/ossec/data/financial_records"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the sensitive directory inside the container
echo "Creating sensitive directory: $TARGET_DIR"
docker exec "${CONTAINER}" mkdir -p "$TARGET_DIR"

# 2. Populate it with "sensitive" files (enough to trigger the frequency rule)
echo "Populating directory with sample files..."
docker exec "${CONTAINER}" bash -c "for i in {1..20}; do touch $TARGET_DIR/invoice_\$i.pdf; done"
docker exec "${CONTAINER}" bash -c "for i in {1..20}; do touch $TARGET_DIR/ledger_2023_\$i.xlsx; done"

# Set permissions so ossec can read them (though root runs syscheck)
docker exec "${CONTAINER}" chown -R root:wazuh "$TARGET_DIR"
docker exec "${CONTAINER}" chmod -R 660 "$TARGET_DIR"

# 3. Ensure a clean state for local_rules.xml (backup existing if needed)
echo "Backing up local_rules.xml..."
docker exec "${CONTAINER}" cp /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.bak

# 4. Open Wazuh Dashboard
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record initial count of alerts for rule 100250 (should be 0)
INITIAL_ALERTS=$(docker exec "${CONTAINER}" grep "\"rule\":{\"id\":\"100250\"" /var/ossec/logs/alerts/alerts.json 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_ALERTS" > /tmp/initial_alert_count.txt

echo "=== Setup complete ==="
echo "Target Directory: $TARGET_DIR"
echo "Required Rule ID: 100250"