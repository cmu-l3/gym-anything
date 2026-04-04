#!/bin/bash
# Setup script for pci_dss_compliance_controls
# Removes any pre-existing PCI controls and records baseline state.

echo "=== Setting up pci_dss_compliance_controls ==="

source /workspace/scripts/task_utils.sh

if ! type wazuh_exec &>/dev/null; then
    echo "Warning: task_utils.sh not fully loaded, using inline definitions"
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

MAX_WAIT=60
WAITED=0
until docker ps | grep -q "wazuh.manager"; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "ERROR: wazuh.manager not running after ${MAX_WAIT}s"
        exit 1
    fi
done

# --- Clean up any pre-existing PCI SCA policies ---
echo "Removing any pre-existing PCI SCA policies..."
wazuh_exec "find /var/ossec/etc/shared -name '*.yaml' -o -name '*.yml' | xargs grep -l -i 'pci\|payment.*card\|cardholder' 2>/dev/null | xargs rm -f 2>/dev/null || true"
wazuh_exec "find /var/ossec/etc/shared -name '*pci*' -o -name '*payment*' 2>/dev/null | xargs rm -f 2>/dev/null || true"

# --- Remove any prior compliance report ---
rm -f /home/ga/Desktop/pci_compliance_report.txt 2>/dev/null || true

# --- Record baseline state ---

INITIAL_RULE_COUNT=0
RULE_COUNT_OUT=$(wazuh_exec "grep -c '<rule id=' /var/ossec/etc/rules/local_rules.xml 2>/dev/null")
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_RULE_COUNT=$RULE_COUNT_OUT
fi
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count
echo "Baseline rule count: $INITIAL_RULE_COUNT"

# Baseline: SCA policy count
INITIAL_SCA_COUNT=0
SCA_COUNT_OUT=$(wazuh_exec "find /var/ossec/etc/shared -name '*.yaml' -o -name '*.yml' 2>/dev/null | wc -l")
if echo "$SCA_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_SCA_COUNT=$SCA_COUNT_OUT
fi
echo "$INITIAL_SCA_COUNT" > /tmp/initial_sca_count
echo "Baseline SCA policy count: $INITIAL_SCA_COUNT"

# Baseline: email alerting configured?
INITIAL_EMAIL=0
if wazuh_exec "grep -q '<email_to>' /var/ossec/etc/ossec.conf 2>/dev/null"; then
    INITIAL_EMAIL=1
fi
echo "$INITIAL_EMAIL" > /tmp/initial_email_configured
echo "Baseline email configured: $INITIAL_EMAIL"

# Ensure email is NOT pre-configured (clean state for this task)
if [ "$INITIAL_EMAIL" -eq 1 ]; then
    echo "Note: Email was already configured — agent must verify or update it"
fi

# --- Record timestamp ---
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Launch Firefox on Wazuh dashboard
if type ensure_firefox_wazuh &>/dev/null; then
    ensure_firefox_wazuh 2>/dev/null || true
else
    su - ga -c "DISPLAY=:1 firefox --new-window 'https://localhost' &" 2>/dev/null || true
fi
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
