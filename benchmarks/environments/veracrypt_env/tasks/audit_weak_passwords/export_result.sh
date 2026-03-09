#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOL_DIR="/home/ga/Volumes"
REPORT_PATH="/home/ga/Documents/audit_report.json"

# 1. Verify Report Existence
REPORT_EXISTS="false"
REPORT_CONTENT="{}"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH")
fi

# 2. Verify Vulnerable Volume (archive_bravo.hc) Status

# Test A: Does the OLD weak password ('princess') still work?
# If it works, the agent FAILED to change it.
OLD_PWD_WORKS="false"
mkdir -p /tmp/vc_test_old
if veracrypt --text --mount "$VOL_DIR/archive_bravo.hc" /tmp/vc_test_old \
    --password='princess' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive 2>/dev/null; then
    OLD_PWD_WORKS="true"
    veracrypt --text --dismount /tmp/vc_test_old --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_test_old 2>/dev/null || true

# Test B: Does the NEW strong password ('Audited&Secured#2026') work?
# If it works, the agent SUCCEEDED in changing it.
NEW_PWD_WORKS="false"
mkdir -p /tmp/vc_test_new
if veracrypt --text --mount "$VOL_DIR/archive_bravo.hc" /tmp/vc_test_new \
    --password='Audited&Secured#2026' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive 2>/dev/null; then
    NEW_PWD_WORKS="true"
    veracrypt --text --dismount /tmp/vc_test_new --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_test_new 2>/dev/null || true

# 3. Verify Non-Vulnerable Volumes (Anti-Tamper Check)
# Alpha should still open with 'Xk9#m2$vLp'
ALPHA_INTEGRITY="false"
mkdir -p /tmp/vc_test_alpha
if veracrypt --text --mount "$VOL_DIR/archive_alpha.hc" /tmp/vc_test_alpha \
    --password='Xk9#m2$vLp' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive 2>/dev/null; then
    ALPHA_INTEGRITY="true"
    veracrypt --text --dismount /tmp/vc_test_alpha --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_test_alpha 2>/dev/null || true

# Charlie should still open with '7d!Qz@1M4'
CHARLIE_INTEGRITY="false"
mkdir -p /tmp/vc_test_charlie
if veracrypt --text --mount "$VOL_DIR/archive_charlie.hc" /tmp/vc_test_charlie \
    --password='7d!Qz@1M4' --pim=0 --keyfiles="" --protect-hidden=no --non-interactive 2>/dev/null; then
    CHARLIE_INTEGRITY="true"
    veracrypt --text --dismount /tmp/vc_test_charlie --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_test_charlie 2>/dev/null || true


# 4. Check application state
APP_RUNNING="false"
if is_veracrypt_running; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare result JSON
# Note: We embed the report content (escaping quotes) to pass to python verifier
SAFE_REPORT_CONTENT=$(echo "$REPORT_CONTENT" | jq -c . 2>/dev/null || echo "{}")

cat > /tmp/raw_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_content": $SAFE_REPORT_CONTENT,
    "vulnerable_vol_old_pwd_works": $OLD_PWD_WORKS,
    "vulnerable_vol_new_pwd_works": $NEW_PWD_WORKS,
    "alpha_integrity": $ALPHA_INTEGRITY,
    "charlie_integrity": $CHARLIE_INTEGRITY,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
write_result_json "/tmp/task_result.json" "$(cat /tmp/raw_result.json)"
rm -f /tmp/raw_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="