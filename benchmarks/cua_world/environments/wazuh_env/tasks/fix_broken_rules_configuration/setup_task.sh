#!/bin/bash
# Setup script for fix_broken_rules_configuration task
echo "=== Setting up fix_broken_rules_configuration task ==="

source /workspace/scripts/task_utils.sh

# Define the broken XML content
# Errors:
# 1. Duplicate ID 100200
# 2. level="medium" (invalid, should be int)
# 3. <description>...<description> (missing closing slash)
cat > /tmp/broken_rules.xml << 'EOF'
<group name="custom_payment_rules,">
  <!-- Rule 1: Critical Payment Error -->
  <rule id="100200" level="12">
    <if_sid>5710</if_sid>
    <match>payment_gateway_error</match>
    <description>Critical Payment Gateway Failure</description>
  </rule>

  <!-- Rule 2: Transaction Slow Warning -->
  <!-- ERROR: Duplicate ID 100200 (should be unique, e.g., 100201) -->
  <!-- ERROR: level="medium" (must be an integer) -->
  <rule id="100200" level="medium">
    <if_sid>5710</if_sid>
    <match>transaction_slow</match>
    <description>Payment Transaction Slow</description>
  </rule>

  <!-- Rule 3: API Not Found -->
  <rule id="100202" level="3">
    <if_sid>5710</if_sid>
    <match>api_404</match>
    <!-- ERROR: Syntax error, missing slash in closing tag -->
    <description>API Endpoint Not Found<description>
  </rule>
</group>
EOF

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Backup existing rules (standard hygiene)
echo "Backing up existing local_rules.xml..."
docker exec "${CONTAINER}" cp /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.bak

# Inject the broken rules
echo "Injecting broken configuration..."
docker cp /tmp/broken_rules.xml "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart Wazuh Manager to trigger the crash
# We use docker restart to ensure the container picks up the failure state
echo "Restarting Wazuh Manager to apply broken config (expecting failure)..."
docker restart "${CONTAINER}"

# Create the ticket note for context
cat > /home/ga/ticket_details.txt << 'EOF'
TICKET #49201: Wazuh SIEM Down
PRIORITY: HIGH
ASSIGNED TO: Security Engineering Team

DESCRIPTION:
I attempted to push some new detection rules for the Payment Gateway application this morning, but immediately after applying the config, the Wazuh Manager service crashed and won't come back up.

I was trying to add:
1. A Critical alert (ID 100200) for "payment_gateway_error".
2. A Warning alert for "transaction_slow".

Attached is the file I uploaded. Now the dashboard says "Manager disconnected". Please fix this ASAP! We need both rules active.

- Junior Analyst
EOF
chown ga:ga /home/ga/ticket_details.txt

# Ensure Firefox is running (it will likely show connection error or dashboard)
echo "Ensuring Firefox is running..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="