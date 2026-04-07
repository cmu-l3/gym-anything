#!/bin/bash
set -e
echo "=== Setting up Create Audit Trail Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running and ready
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Clean up previous state to ensure a fair test
echo "Cleaning up database state..."
mysql -u root DrTuxTest <<EOF 2>/dev/null || true
DROP TABLE IF EXISTS patient_audit_log;
DROP TRIGGER IF EXISTS trg_index_after_insert;
DROP TRIGGER IF EXISTS trg_index_after_update;
DROP TRIGGER IF EXISTS trg_index_after_delete;
DROP TRIGGER IF EXISTS trg_fchpat_after_insert;
DROP TRIGGER IF EXISTS trg_fchpat_after_update;
DROP TRIGGER IF EXISTS trg_fchpat_after_delete;
DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('AUDIT-TEST-001', 'AUDIT-VERIFY-001');
DELETE FROM fchpat WHERE FchPat_GUID_Doss IN ('AUDIT-TEST-001', 'AUDIT-VERIFY-001');
EOF

# Clean up report file
rm -f /home/ga/audit_trail_report.txt

# Ensure MedinTux Manager is running (provides context, though mostly DB task)
# This uses the utility from task_utils.sh which handles Qt DLLs and window waiting
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="