#!/bin/bash
# Setup: Create and deploy the ADT_Inbound_Processor channel, ensure no alerts exist
set -e
echo "=== Setting up configure_error_alert task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120 || { echo "ERROR: API not ready"; exit 1; }

sleep 5

# Remove any existing alerts
echo "Clearing existing alerts..."
EXISTING_ALERTS=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/alerts" 2>/dev/null)

# Parse alert IDs and delete them (using python for robust XML parsing)
echo "$EXISTING_ALERTS" | python3 -c "
import sys
from xml.etree import ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    for alert in root.iter('alertModel'):
        aid = alert.find('id')
        if aid is not None and aid.text:
            print(aid.text)
except:
    pass
" 2>/dev/null | while read alert_id; do
    echo "Deleting alert: $alert_id"
    curl -sk -X DELETE -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/alerts/${alert_id}" 2>/dev/null
done

# Remove any existing channels to ensure clean state
echo "Clearing existing channels..."
EXISTING_CHANNELS=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/channels" 2>/dev/null)

echo "$EXISTING_CHANNELS" | python3 -c "
import sys
from xml.etree import ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    for ch in root.iter('channel'):
        cid = ch.find('id')
        if cid is not None and cid.text:
            print(cid.text)
except:
    pass
" 2>/dev/null | while read ch_id; do
    echo "Undeploying and deleting channel: $ch_id"
    curl -sk -X POST -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/channels/${ch_id}/_undeploy" 2>/dev/null || true
    sleep 1
    curl -sk -X DELETE -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/channels/${ch_id}" 2>/dev/null || true
done

sleep 3

# Define fixed channel ID for consistent verification
ADT_CHANNEL_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"

# Create the ADT_Inbound_Processor channel
echo "Creating ADT_Inbound_Processor channel..."
ADT_CHANNEL_XML=$(cat <<'XMLEOF'
<channel version="4.5.0">
  <id>a1b2c3d4-e5f6-7890-abcd-ef1234567890</id>
  <nextMetaDataId>2</nextMetaDataId>
  <name>ADT_Inbound_Processor</name>
  <description>Receives ADT (Admit/Discharge/Transfer) HL7v2 messages from the hospital registration system via MLLP. Routes messages to downstream clinical systems.</description>
  <revision>1</revision>
  <sourceConnector version="4.5.0">
    <metaDataId>0</metaDataId>
    <transportName>TCP Listener</transportName>
    <mode>SOURCE</mode>
    <enabled>true</enabled>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties/>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>6661</port>
      </listenerConnectorProperties>
      <sourceConnectorProperties version="4.5.0">
        <responseVariable>None</responseVariable>
        <respondAfterProcessing>true</respondAfterProcessing>
        <processBatch>false</processBatch>
        <firstResponse>false</firstResponse>
        <processingThreads>1</processingThreads>
        <resourceIds class="linked-hash-map">
          <entry>
            <string>Default Resource</string>
            <string>[Default Resource]</string>
          </entry>
        </resourceIds>
      </sourceConnectorProperties>
    </properties>
    <transformer version="4.5.0">
      <elements/>
      <inboundDataType>HL7V2</inboundDataType>
      <outboundDataType>HL7V2</outboundDataType>
    </transformer>
    <filter version="4.5.0">
      <elements/>
    </filter>
  </sourceConnector>
  <destinationConnectors>
    <connector version="4.5.0">
      <metaDataId>1</metaDataId>
      <transportName>Channel Writer</transportName>
      <name>Destination 1</name>
      <mode>DESTINATION</mode>
      <enabled>true</enabled>
      <properties class="com.mirth.connect.connectors.core.channel.ChannelWriterProperties" version="4.5.0" />
      <transformer version="4.5.0">
        <elements/>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
      </transformer>
      <filter version="4.5.0">
        <elements/>
      </filter>
    </connector>
  </destinationConnectors>
  <properties version="4.5.0">
    <clearGlobalChannelMap>true</clearGlobalChannelMap>
    <messageStorageMode>DEVELOPMENT</messageStorageMode>
    <encryptData>false</encryptData>
    <initialState>STARTED</initialState>
    <storeAttachments>false</storeAttachments>
    <metaDataColumns/>
    <attachmentProperties version="4.5.0">
      <type>None</type>
      <properties/>
    </attachmentProperties>
    <resourceIds class="linked-hash-map">
      <entry>
        <string>Default Resource</string>
        <string>[Default Resource]</string>
      </entry>
    </resourceIds>
  </properties>
</channel>
XMLEOF
)

# Create the channel via API
HTTP_CODE=$(curl -sk -o /tmp/channel_create_response.txt -w "%{http_code}" \
    -X POST \
    -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Content-Type: application/xml" \
    -d "$ADT_CHANNEL_XML" \
    "https://localhost:8443/api/channels" 2>/dev/null)

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "ERROR: Failed to create channel (HTTP $HTTP_CODE)"
    cat /tmp/channel_create_response.txt
    exit 1
fi

sleep 3

# Deploy the channel
echo "Deploying ADT_Inbound_Processor channel..."
curl -sk -X POST \
    -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Content-Type: application/json" \
    -d '{"channelIds":["a1b2c3d4-e5f6-7890-abcd-ef1234567890"],"returnErrors":true}' \
    "https://localhost:8443/api/channels/_deploy" 2>/dev/null

sleep 5

# Save the channel ID for verification
echo "a1b2c3d4-e5f6-7890-abcd-ef1234567890" > /tmp/adt_channel_id.txt

# Record alert count (should be 0)
ALERT_COUNT=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/alerts" 2>/dev/null | grep -c "alertModel" || echo "0")
echo "${ALERT_COUNT:-0}" > /tmp/initial_alert_count.txt

# Ensure Firefox is showing the landing page
echo "Refreshing Firefox..."
su - ga -c "DISPLAY=:1 xdotool key F5" 2>/dev/null || true
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "ADT_Inbound_Processor channel created with ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890"