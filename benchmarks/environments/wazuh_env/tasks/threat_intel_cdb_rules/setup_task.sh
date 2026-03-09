#!/bin/bash
# pre_task: Setup for threat_intel_cdb_rules
echo "=== Setting up threat_intel_cdb_rules ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
SOURCE_URL="https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
STAGED_FILE="/tmp/feodotracker_c2_ips.txt"

# Download the real Feodo Tracker C2 IP blocklist from abuse.ch
echo "Downloading Feodo Tracker C2 IP blocklist from abuse.ch..."
if ! curl -sk --max-time 60 -A "Mozilla/5.0" "$SOURCE_URL" -o "$STAGED_FILE"; then
    echo "ERROR: Failed to download Feodo Tracker blocklist from $SOURCE_URL"
    echo "This task requires a real threat intelligence feed. Check network connectivity."
    exit 1
fi

# Verify the download has content
if [ ! -s "$STAGED_FILE" ]; then
    echo "ERROR: Downloaded file is empty. Cannot proceed without real threat intelligence data."
    exit 1
fi

# Count valid IP entries (non-comment lines matching IP format)
IP_COUNT=$(grep -cE "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" "$STAGED_FILE" 2>/dev/null)
[ -z "$IP_COUNT" ] && IP_COUNT=0

echo "Downloaded $IP_COUNT valid C2 IP entries from Feodo Tracker (abuse.ch)"

if [ "$IP_COUNT" -lt 1 ]; then
    echo "ERROR: No valid IP entries found in downloaded blocklist. Task requires real threat intelligence data."
    exit 1
fi

echo "Threat intelligence staged at: $STAGED_FILE"
echo "Sample entries:"
grep -E "^[0-9]" "$STAGED_FILE" | head -5

# Remove any prior threat intel CDB lists from previous task runs (clean state)
echo ""
echo "Cleaning up any prior CDB lists containing IP addresses..."
docker exec "${CONTAINER}" bash -c '
for f in /var/ossec/etc/lists/*; do
    [ -f "$f" ] || continue
    case "$f" in *.db|*.cdb) continue;; esac
    # Only remove non-built-in lists that have IP content
    fname=$(basename "$f")
    case "$fname" in audit-keys|security-eventchannel|amazon-*) continue;; esac
    if grep -qE "^[0-9]{1,3}\.[0-9]{1,3}" "$f" 2>/dev/null; then
        echo "Removing prior threat intel list: $f"
        rm -f "$f" "${f}.db" "${f}.cdb" 2>/dev/null || true
    fi
done
' 2>/dev/null || true

# Reset local_rules.xml to baseline (remove any prior CDB-based threat intel rules)
echo "Resetting local_rules.xml to baseline (rules 100001-100003 only)..."
BASELINE_RULES='<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible brute force</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Failed sudo attempts -->
  <rule id="100002" level="8">
    <if_sid>5401</if_sid>
    <match>incorrect password attempts</match>
    <description>Failed sudo attempt detected</description>
    <group>sudo_failed,authentication_failed,</group>
  </rule>

  <!-- High CPU usage alert -->
  <rule id="100003" level="7">
    <if_sid>530</if_sid>
    <match>CPU usage is high</match>
    <description>High CPU usage detected on agent</description>
    <group>system_monitor,</group>
  </rule>

</group>'

TEMP_RULES=$(mktemp /tmp/rules_reset.XXXXXX.xml)
echo "$BASELINE_RULES" > "$TEMP_RULES"
docker cp "$TEMP_RULES" "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" && \
    echo "Rules reset to baseline" || echo "WARNING: Could not reset rules"
rm -f "$TEMP_RULES"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# Record baseline state
echo "Recording baseline state..."
INITIAL_LIST_COUNT=$(docker exec "${CONTAINER}" bash -c \
    'ls /var/ossec/etc/lists/ 2>/dev/null | grep -cvE "\.db$|\.cdb$"' 2>/dev/null)
[ -z "$INITIAL_LIST_COUNT" ] && INITIAL_LIST_COUNT=0
echo "$INITIAL_LIST_COUNT" > /tmp/initial_cdb_list_count

INITIAL_RULE_COUNT=$(docker exec "${CONTAINER}" grep -c "<rule " \
    /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
[ -z "$INITIAL_RULE_COUNT" ] && INITIAL_RULE_COUNT=0
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Wazuh dashboard
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3
navigate_firefox_to "${WAZUH_URL_HOME}"
sleep 5

take_screenshot /tmp/threat_intel_cdb_rules_start.png
echo "Initial screenshot saved."

echo ""
echo "=== Setup Complete ==="
echo "Threat intelligence data available at: ${STAGED_FILE}"
echo "File contains ${IP_COUNT} real Feodo Tracker botnet C2 IP addresses from abuse.ch"
echo "Task: Integrate these IPs into Wazuh using CDB lists and custom detection rules"
echo "      Any network activity involving these IPs should trigger level 9+ alerts"
