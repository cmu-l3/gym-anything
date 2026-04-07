#!/bin/bash
echo "=== Setting up compliance_audit_exam_setup task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json \
    /tmp/compliance_audit_exam_setup_result.json \
    /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline database state
record_baseline "compliance_audit_exam_setup"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent must implement GDPR compliance configuration:"
echo "  1. Create exam config 'GDPR Compliant Exam Config' with GDPR description"
echo "  2. Create connection config 'Privacy-First Connection' (no fallback)"
echo "  3. Create exam template 'GDPR Exam Template'"
echo "  4. Add indicator 'Minimal Monitoring' (LAST_PING_TIME, warn:5000, danger:15000)"
echo "  5. Create user 'dpo.officer' (Ingrid Larsson) as Exam Administrator"
