#!/bin/bash
# pre_task: Setup for sca_custom_policy_report
echo "=== Setting up sca_custom_policy_report ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
REPORT_PATH="/home/ga/Desktop/compliance_report.txt"

# Remove any prior compliance report from previous task runs
echo "Removing any prior compliance report..."
rm -f "$REPORT_PATH" 2>/dev/null || true

# Remove any prior custom SCA policy YAML files from previous runs
echo "Cleaning up prior custom SCA policy files..."
docker exec "${CONTAINER}" bash -c '
DEFAULT_PATTERNS="cis_ubuntu cis_debian cis_centos cis_rhel cis_sles cis_apple cis_win"
for f in /var/ossec/etc/shared/*.yml /var/ossec/etc/shared/*.yaml \
          /var/ossec/etc/shared/default/*.yml /var/ossec/etc/shared/default/*.yaml; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    is_default=0
    for pat in $DEFAULT_PATTERNS; do
        echo "$fname" | grep -q "$pat" && is_default=1 && break
    done
    if [ "$is_default" -eq 0 ]; then
        echo "Removing prior custom SCA policy: $f"
        rm -f "$f" 2>/dev/null || true
    fi
done
' 2>/dev/null || true

# Verify that the default SCA policy is present and has run
echo "Checking SCA status for agent 000..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    SCA_RESULT=$(curl -sk -X GET "${WAZUH_API_URL}/sca/000" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    echo "SCA policies for agent 000:"
    echo "$SCA_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
if items:
    for p in items:
        print(f\"  Policy: {p.get('name', 'unknown')} | Pass: {p.get('pass', 0)} | Fail: {p.get('fail', 0)} | Score: {p.get('score', 0)}%\")
else:
    print('  (No SCA data yet — first scan may still be running)')
" 2>/dev/null || echo "  (could not parse SCA data)"
fi

# Record baseline state
echo "Recording baseline state..."
INITIAL_CUSTOM_POLICY_COUNT=$(docker exec "${CONTAINER}" bash -c '
count=0
DEFAULT_PATTERNS="cis_ubuntu cis_debian cis_centos cis_rhel cis_sles cis_apple cis_win"
for f in /var/ossec/etc/shared/*.yml /var/ossec/etc/shared/*.yaml \
          /var/ossec/etc/shared/default/*.yml; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    is_default=0
    for pat in $DEFAULT_PATTERNS; do
        echo "$fname" | grep -q "$pat" && is_default=1 && break
    done
    [ "$is_default" -eq 0 ] && count=$((count + 1))
done
echo $count
' 2>/dev/null || echo "0")
[ -z "$INITIAL_CUSTOM_POLICY_COUNT" ] && INITIAL_CUSTOM_POLICY_COUNT=0
echo "$INITIAL_CUSTOM_POLICY_COUNT" > /tmp/initial_custom_policy_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Wazuh dashboard at the SCA overview
echo "Opening Wazuh dashboard at SCA overview..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3
navigate_firefox_to "${WAZUH_URL_SCA}"
sleep 6

take_screenshot /tmp/sca_custom_policy_report_start.png
echo "Initial screenshot saved."

echo ""
echo "=== Setup Complete ==="
echo "SCA data is available in the Wazuh dashboard for agent 000"
echo "Initial custom SCA policy count: ${INITIAL_CUSTOM_POLICY_COUNT}"
echo "Task: Review SCA results, create custom YAML policy (3+ checks), configure Wazuh,"
echo "      write compliance gap analysis to: ${REPORT_PATH}"
echo ""
echo "Wazuh SCA YAML policy schema: https://documentation.wazuh.com/current/user-manual/capabilities/sec-config-assessment/creating-custom-policies.html"
