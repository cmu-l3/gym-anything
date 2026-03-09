#!/bin/bash
echo "=== Exporting firewall task results ==="

# Source utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. CAPTURE FINAL STATE
take_screenshot /tmp/task_final.png

# 2. GATHER DATA
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_rule_count.txt 2>/dev/null || echo "0")

# Check iptables live status
# We look for specific signatures in the output
IPTABLES_OUTPUT=$(iptables -L INPUT -n -v 2>/dev/null)
CURRENT_COUNT=$(echo "$IPTABLES_OUTPUT" | grep -c "^[0-9]")

# Check for Port 8443
if echo "$IPTABLES_OUTPUT" | grep -qE "ACCEPT.*tcp.*dpt:8443"; then
    RULE_8443_EXISTS="true"
else
    RULE_8443_EXISTS="false"
fi

# Check for Port 9090
if echo "$IPTABLES_OUTPUT" | grep -qE "ACCEPT.*tcp.*dpt:9090"; then
    RULE_9090_EXISTS="true"
else
    RULE_9090_EXISTS="false"
fi

# Check for IP Block (accept DROP or REJECT)
if echo "$IPTABLES_OUTPUT" | grep -qE "(DROP|REJECT).*198\.51\.100\.0/24"; then
    RULE_BLOCK_EXISTS="true"
else
    RULE_BLOCK_EXISTS="false"
fi

# Check if baseline rules were preserved
# We expect at least the count to be Initial + 3 (approx)
# A destructive agent might wipe everything (count < initial)
RULES_PRESERVED="true"
if echo "$IPTABLES_OUTPUT" | grep -q "dpt:10000"; then
     : # Webmin still accessible
else
     RULES_PRESERVED="false"
fi

# Check Webmin configuration file timestamp (to see if "Apply" was likely clicked)
# Webmin usually writes to /etc/webmin/firewall/*.save or system iptables file
CONFIG_MODIFIED="false"
for f in /etc/iptables.up.rules /etc/webmin/firewall/iptables.save; do
    if [ -f "$f" ]; then
        F_TIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$F_TIME" -gt "$TASK_START" ]; then
            CONFIG_MODIFIED="true"
        fi
    fi
done

# 3. CREATE RESULT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_rule_count": $INITIAL_COUNT,
    "current_rule_count": $CURRENT_COUNT,
    "rule_8443_exists": $RULE_8443_EXISTS,
    "rule_9090_exists": $RULE_9090_EXISTS,
    "rule_block_exists": $RULE_BLOCK_EXISTS,
    "baseline_preserved": $RULES_PRESERVED,
    "config_file_modified": $CONFIG_MODIFIED,
    "iptables_dump_excerpt": "$(echo "$IPTABLES_OUTPUT" | head -n 20 | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json