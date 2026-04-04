#!/bin/bash
echo "=== Setting up process_hl7_message task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy sample HL7 ADT message to home directory for easy access
echo "Copying sample HL7 message..."
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_message.hl7
chown ga:ga /home/ga/sample_adt_message.hl7 2>/dev/null || true
chmod 644 /home/ga/sample_adt_message.hl7

# Also copy to /tmp for alternative access
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /tmp/sample_adt_message.hl7
chmod 666 /tmp/sample_adt_message.hl7 2>/dev/null || true

# Pre-create a basic HL7 channel so the task is self-contained
# (agent needs to send a message through it, not create the channel)
echo "Creating HL7 processing channel..."
CHANNEL_XML='<?xml version="1.0" encoding="UTF-8"?>
<channel version="4.5.0">
  <id>proc-hl7-msg-channel-01</id>
  <name>HL7 Message Processor</name>
  <description>Pre-created channel for HL7 message processing</description>
  <enabled>true</enabled>
  <sourceConnector version="4.5.0">
    <transportName>TCP Listener</transportName>
    <mode>SOURCE</mode>
    <enabled>true</enabled>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties>
        <com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties version="4.5.0">
          <serializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties" version="4.5.0">
            <handleRepetitions>true</handleRepetitions>
            <handleSubcomponents>true</handleSubcomponents>
            <useStrictParser>false</useStrictParser>
            <useStrictValidation>false</useStrictValidation>
            <stripNamespaces>true</stripNamespaces>
            <segmentDelimiter>\\r</segmentDelimiter>
            <convertLineBreaks>true</convertLineBreaks>
          </com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties>
        </com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties>
      </pluginProperties>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>6661</port>
      </listenerConnectorProperties>
      <sourceConnectorProperties version="4.5.0">
        <responseVariable>None</responseVariable>
      </sourceConnectorProperties>
      <serverMode>true</serverMode>
      <remoteAddress></remoteAddress>
      <remotePort></remotePort>
      <overrideLocalBinding>false</overrideLocalBinding>
      <reconnectInterval>5000</reconnectInterval>
      <receiveTimeout>0</receiveTimeout>
      <bufferSize>65536</bufferSize>
      <maxConnections>10</maxConnections>
      <keepConnectionOpen>true</keepConnectionOpen>
      <dataTypeBinary>false</dataTypeBinary>
      <charsetEncoding>DEFAULT_ENCODING</charsetEncoding>
      <respondOnNewConnection>0</respondOnNewConnection>
      <responseAddress></responseAddress>
      <responsePort></responsePort>
      <transmissionModeProperties class="com.mirth.connect.plugins.mllpmode.MLLPModeProperties" version="4.5.0">
        <pluginPointName>MLLP</pluginPointName>
        <startOfMessageBytes>0B</startOfMessageBytes>
        <endOfMessageBytes>1C0D</endOfMessageBytes>
        <useMLLPv2>false</useMLLPv2>
        <ackBytes>06</ackBytes>
        <nackBytes>15</nackBytes>
        <maxRetries>0</maxRetries>
      </transmissionModeProperties>
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
      <name>File Writer</name>
      <transportName>File Writer</transportName>
      <mode>DESTINATION</mode>
      <enabled>true</enabled>
      <properties class="com.mirth.connect.connectors.file.FileDispatcherProperties" version="4.5.0">
        <pluginProperties/>
        <destinationConnectorProperties version="4.5.0"/>
        <host>/tmp/hl7_output</host>
        <outputPattern>msg_${message.encodedData.hashCode()}.hl7</outputPattern>
        <anonymous>true</anonymous>
        <scheme>FILE</scheme>
        <outputAppend>false</outputAppend>
        <errorOnExists>false</errorOnExists>
        <temporary>false</temporary>
        <binary>false</binary>
        <charsetEncoding>DEFAULT_ENCODING</charsetEncoding>
      </properties>
      <transformer version="4.5.0">
        <elements/>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
      </transformer>
      <responseTransformer version="4.5.0">
        <elements/>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
      </responseTransformer>
      <filter version="4.5.0">
        <elements/>
      </filter>
    </connector>
  </destinationConnectors>
  <preprocessingScript>return message;</preprocessingScript>
  <postprocessingScript>return;</postprocessingScript>
  <deployScript>return;</deployScript>
  <undeployScript>return;</undeployScript>
</channel>'

# Create channel via API
CREATE_RESPONSE=$(curl -sk -X POST \
    -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Content-Type: application/xml" \
    -d "$CHANNEL_XML" \
    "https://localhost:8443/api/channels" 2>/dev/null)
echo "Channel creation response: $CREATE_RESPONSE"

# Deploy the channel
sleep 2
curl -sk -X POST \
    -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    "https://localhost:8443/api/channels/_redeployAll" 2>/dev/null
echo "Channel deployment triggered"

# Wait for deployment
sleep 5

# Record initial received count (for delta-based verification)
CHANNEL_ID=$(query_postgres "SELECT id FROM channel LIMIT 1;" 2>/dev/null || true)
INITIAL_RECEIVED=0
if [ -n "$CHANNEL_ID" ]; then
    STATS_JSON=$(curl -sk -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Accept: application/json" \
        "https://localhost:8443/api/channels/$CHANNEL_ID/statistics" 2>/dev/null)
    INITIAL_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
fi
rm -f /tmp/initial_received_count 2>/dev/null || sudo rm -f /tmp/initial_received_count 2>/dev/null || true
printf '%s' "$INITIAL_RECEIVED" > /tmp/initial_received_count 2>/dev/null || true
echo "Initial received count: $INITIAL_RECEIVED"

echo "Sample message available at: /home/ga/sample_adt_message.hl7"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - HL7 Message Processing"
echo "============================================"
echo ""
echo "TASK: Send an HL7 ADT message through the channel"
echo ""
echo "Sample message: /home/ga/sample_adt_message.hl7"
echo "Channel is listening on port 6661 (MLLP mode)"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo ""
echo "Web Dashboard (monitoring): https://localhost:8443"
echo "PostgreSQL: docker exec nextgen-postgres psql -U postgres -d mirthdb"
echo ""
echo "Tools: curl, nc (netcat), docker, python3"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
