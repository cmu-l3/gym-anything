#!/bin/bash
echo "=== Exporting configure_email_auth_dns results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Export current DNS configuration for verification
# We export the full DNS dump for the domain
virtualmin get-dns --domain localbiz.test > /tmp/final_dns_records.txt 2>/dev/null || echo "Error getting DNS" > /tmp/final_dns_records.txt

# 2. Get current Serial
FINAL_SERIAL=$(virtualmin get-dns --domain localbiz.test | grep "SOA" | grep -oE '[0-9]{10}' | head -1 || echo "0")
INITIAL_SERIAL=$(cat /tmp/initial_dns_serial.txt 2>/dev/null || echo "0")

# 3. Check specific records using dig (independent verification)
# We query the local BIND server directly
DIG_SPF=$(dig @localhost localbiz.test TXT +short 2>/dev/null | grep "v=spf1")
DIG_DMARC=$(dig @localhost _dmarc.localbiz.test TXT +short 2>/dev/null | grep "v=DMARC1")

# 4. Verify Zone File modification time
ZONE_FILE="/var/lib/bind/localbiz.test.hosts"
ZONE_MODIFIED="false"
if [ -f "$ZONE_FILE" ]; then
    ZONE_MTIME=$(stat -c %Y "$ZONE_FILE")
    if [ "$ZONE_MTIME" -gt "$TASK_START" ]; then
        ZONE_MODIFIED="true"
    fi
fi

# 5. Construct JSON Result
# Using a python script to safely generate JSON to avoid shell escaping hell
python3 << EOF
import json
import os

try:
    with open('/tmp/final_dns_records.txt', 'r') as f:
        dns_dump = f.read()
except:
    dns_dump = ""

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_serial": "$INITIAL_SERIAL",
    "final_serial": "$FINAL_SERIAL",
    "zone_modified_timestamp": $ZONE_MODIFIED,
    "dig_spf": """$DIG_SPF""",
    "dig_dmarc": """$DIG_DMARC""",
    "dns_records_dump": dns_dump,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Set permissions so verifier can copy it (if running as different user)
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json