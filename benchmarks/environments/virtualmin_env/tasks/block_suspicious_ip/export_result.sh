#!/bin/bash
echo "=== Exporting block_suspicious_ip results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Firewall State
echo "Exporting firewall rules..."
iptables-save > /tmp/iptables_rules.txt 2>/dev/null || true
# Also try firewalld if present
if command -v firewall-cmd >/dev/null; then
    firewall-cmd --list-all > /tmp/firewalld_rules.txt 2>/dev/null || true
fi

# 2. Check Report File
REPORT_FILE="/home/ga/blocked_attacker.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 1) # Read first line
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# 3. Evidence Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g')",
    "report_mtime": $REPORT_MTIME,
    "firewall_rules_path": "/tmp/iptables_rules.txt",
    "firewalld_rules_path": "/tmp/firewalld_rules.txt"
}
EOF

# Move files for extraction
# We need to ensure the verifier (outside) can read these.
# The framework copies files out. We'll group them into a standard location if needed,
# or just rely on the framework copying specific paths.
# Since we only get `copy_from_env`, we should consolidate into one file or rely on
# copying specific known paths.
# We'll put everything important into /tmp/task_result.json and ensure the text files stay in /tmp
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json
chmod 644 /tmp/iptables_rules.txt 2>/dev/null || true
chmod 644 /tmp/firewalld_rules.txt 2>/dev/null || true

echo "Export complete. Result json:"
cat /tmp/task_result.json