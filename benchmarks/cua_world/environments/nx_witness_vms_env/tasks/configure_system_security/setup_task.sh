#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up security hardening task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure server is running
systemctl start networkoptix-mediaserver 2>/dev/null || true
sleep 5

# Refresh auth token
NX_TOKEN=$(refresh_nx_token)

# Step 1: Reset all target settings to non-hardened defaults
echo "=== Resetting settings to non-hardened defaults ==="

# Set each setting individually for reliability
for setting_pair in \
    "sessionLimitMinutes:0" \
    "autoDiscoveryEnabled:true" \
    "trafficEncryptionForced:false" \
    "statisticsAllowed:true" \
    "insecureDeprecatedApiEnabled:true"; do
    
    SNAME="${setting_pair%%:*}"
    SVAL="${setting_pair##*:}"
    
    # Try PATCH on the collection or individual endpoint if needed
    # Using PATCH /rest/v1/system/settings is standard for Nx Witness
    curl -sk -X PATCH "${NX_BASE}/rest/v1/system/settings" \
        -H "Authorization: Bearer ${NX_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"${SNAME}\": ${SVAL}}" \
        --max-time 15 2>/dev/null || true
    
    sleep 0.5
done

sleep 3

# Step 2: Record initial settings as baseline (Anti-gaming)
echo "=== Recording baseline settings ==="
SETTINGS_JSON=$(curl -sk "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${NX_TOKEN}" --max-time 15 2>/dev/null || echo "{}")

echo "$SETTINGS_JSON" > /tmp/initial_security_settings.json

# Step 3: Create the agent-visible audit baseline file
# This provides the agent with the "Audit Findings"
python3 -c "
import json, sys
try:
    settings = json.loads('''${SETTINGS_JSON}''')
except:
    settings = {}

baseline = {}
targets = ['sessionLimitMinutes', 'autoDiscoveryEnabled', 'trafficEncryptionForced', 'statisticsAllowed', 'insecureDeprecatedApiEnabled']

for key in targets:
    baseline[key] = settings.get(key, 'UNKNOWN')

with open('/home/ga/security_audit_baseline.json', 'w') as f:
    json.dump(baseline, f, indent=2)
print('Baseline written')
" 2>/dev/null || echo '{"note": "Query settings via API to see current values"}' > /home/ga/security_audit_baseline.json

chown ga:ga /home/ga/security_audit_baseline.json

# Step 4: Remove any old report file
rm -f /home/ga/security_hardening_report.txt

# Step 5: Launch Firefox to web admin
echo "=== Launching Firefox ==="
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
sleep 5
dismiss_ssl_warning
sleep 2
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Security hardening task setup complete ==="