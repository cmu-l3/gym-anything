#!/bin/bash
# Setup for "generate_compliance_report" task
# Opens Firefox to the EventLog Analyzer Compliance/Reports section

echo "=== Setting up Generate Compliance Report task ==="

# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Navigate Firefox to EventLog Analyzer Compliance section
ensure_firefox_on_ela "/event/AppsHome.do#/compliance"
sleep 3

# Take initial screenshot
take_screenshot /tmp/generate_compliance_report_start.png

echo ""
echo "=== Generate Compliance Report Task Ready ==="
echo ""
echo "Instructions:"
echo "  EventLog Analyzer Compliance page is open in Firefox."
echo "  You are logged in as admin."
echo "  You can see compliance standards: FISMA, PCI-DSS, SOX, HIPAA, GLBA, ISO 27001, GDPR."
echo "  Click 'View Reports' under PCI-DSS to generate a compliance report."
echo ""
