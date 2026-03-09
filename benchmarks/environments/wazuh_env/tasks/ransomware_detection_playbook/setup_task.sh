#!/bin/bash
# Setup script for ransomware_detection_playbook
# Seeds ransomware-precursor events into Wazuh and records baseline state.

echo "=== Setting up ransomware_detection_playbook ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils.sh sourcing fails
if ! type wazuh_exec &>/dev/null; then
    echo "Warning: task_utils.sh not fully loaded, using inline definitions"
    wazuh_exec() { docker exec wazuh.manager bash -c "$1" 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# Wait for Wazuh manager container
MAX_WAIT=60
WAITED=0
until docker ps | grep -q "wazuh.manager"; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "ERROR: wazuh.manager container not running after ${MAX_WAIT}s"
        exit 1
    fi
done

echo "Wazuh manager container is running"

# --- Record baseline state ---

# Baseline: number of rules in local_rules.xml
INITIAL_RULE_COUNT=0
RULE_COUNT_OUT=$(wazuh_exec "grep -c '<rule id=' /var/ossec/etc/rules/local_rules.xml 2>/dev/null")
if echo "$RULE_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_RULE_COUNT=$RULE_COUNT_OUT
fi
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count
echo "Baseline rule count: $INITIAL_RULE_COUNT"

# Baseline: active-response count in ossec.conf
INITIAL_AR_COUNT=0
AR_COUNT_OUT=$(wazuh_exec "grep -c '<active-response>' /var/ossec/etc/ossec.conf 2>/dev/null")
if echo "$AR_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_AR_COUNT=$AR_COUNT_OUT
fi
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count
echo "Baseline AR count: $INITIAL_AR_COUNT"

# Baseline: FIM directory entries in ossec.conf
INITIAL_FIM_COUNT=0
FIM_COUNT_OUT=$(wazuh_exec "grep -c '<directories' /var/ossec/etc/ossec.conf 2>/dev/null")
if echo "$FIM_COUNT_OUT" | grep -qE '^[0-9]+$'; then
    INITIAL_FIM_COUNT=$FIM_COUNT_OUT
fi
echo "$INITIAL_FIM_COUNT" > /tmp/initial_fim_count
echo "Baseline FIM directory count: $INITIAL_FIM_COUNT"

# --- Inject ransomware-precursor events (real TTPs) ---
# These represent actual ransomware behavior documented in MITRE ATT&CK:
# T1490 - Inhibit System Recovery (shadow copy deletion)
# T1486 - Data Encrypted for Impact (mass file modification)
# T1021.004 - Remote Services: SSH (lateral movement)

echo "Injecting ransomware-precursor log events..."

# T1490: Shadow copy deletion attempts from multiple hosts
for i in 1 2 3 4 5; do
    wazuh_exec "logger -p syslog.warning 'audit: type=EXECVE msg=audit($(date +%s).${i}:${i}00): argc=5 a0=\"vssadmin\" a1=\"Delete\" a2=\"Shadows\" a3=\"/All\" a4=\"/Quiet\"'"
    sleep 0.1
done

# T1486: Mass file modification with suspicious extensions (encryption pattern)
for ext in encrypted locked crypto WNCRY enc; do
    wazuh_exec "logger -p syslog.info 'audit: type=PATH msg=audit($(date +%s).001:200): item=0 name=\"/home/user/Documents/invoice.pdf.${ext}\" inode=98765 dev=fd:00 mode=0100600 ouid=1001 ogid=1001 nametype=CREATE'"
done

# T1021.004: Lateral movement via SSH from internal hosts
for ip in 192.168.10.5 192.168.10.8 192.168.10.15; do
    wazuh_exec "logger -p auth.info 'sshd: Accepted password for backup from ${ip} port $((50000 + RANDOM % 10000)) ssh2'"
done

# Multiple failed sudo attempts (privilege escalation precursor)
for i in 1 2 3; do
    wazuh_exec "logger -p auth.warning 'sudo: pam_unix(sudo:auth): authentication failure; logname=jdoe uid=1001 euid=0 tty=/dev/pts/0 ruser=jdoe rhost= user=jdoe'"
done

echo "Ransomware-precursor events injected into Wazuh"

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded: $(cat /tmp/task_start_timestamp)"

# --- Ensure Wazuh dashboard is open in Firefox ---
if type ensure_firefox_wazuh &>/dev/null; then
    ensure_firefox_wazuh 2>/dev/null || true
else
    # Fallback: launch Firefox on Wazuh dashboard
    su - ga -c "DISPLAY=:1 firefox --new-window 'https://localhost' &" 2>/dev/null || true
fi
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
