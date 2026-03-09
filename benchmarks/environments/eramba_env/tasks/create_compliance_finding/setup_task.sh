#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up: create_compliance_finding ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Discover the table name for findings (schema robustness)
# Likely candidates: compliance_findings, compliance_analysis_findings, findings
echo "--- Discovering findings table ---"
FINDINGS_TABLE=$(eramba_db_query "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='eramba' AND TABLE_NAME LIKE '%findings%' ORDER BY LENGTH(TABLE_NAME) ASC LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$FINDINGS_TABLE" ]; then
    # Fallback default
    FINDINGS_TABLE="compliance_findings"
fi
echo "$FINDINGS_TABLE" > /tmp/findings_table_name.txt
echo "  Identified findings table: $FINDINGS_TABLE"

# 3. Record initial count
INITIAL_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM ${FINDINGS_TABLE} WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_findings_count.txt
echo "  Initial findings count: $INITIAL_COUNT"

# 4. Ensure Prerequisite: ISO 27001 Compliance Package
# The finding usually needs to be linked to an analysis or package, or at least the module needs to be active.
PACKAGE_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM compliance_packages WHERE deleted=0;" 2>/dev/null || echo "0")
if [ "$PACKAGE_COUNT" = "0" ]; then
    echo "  Seeding ISO 27001 Compliance Package..."
    eramba_db_query "INSERT INTO compliance_packages (name, description, package_provider, version, created, modified, deleted) VALUES ('ISO 27001:2022', 'Information security management systems', 'ISO', '2022', NOW(), NOW(), 0);" 2>/dev/null || true
fi

# 5. Prepare Application State
# Ensure Firefox is running and logged in
ensure_firefox_eramba "http://localhost:8080"
sleep 5

# Navigate to the Compliance module to save the agent some clicks and ensure correct starting context
navigate_firefox_to "http://localhost:8080/compliance/index"
sleep 3

# 6. Capture Initial State Screenshot
take_screenshot /tmp/task_initial_state.png
echo "  Initial screenshot captured"

echo "=== Setup complete ==="