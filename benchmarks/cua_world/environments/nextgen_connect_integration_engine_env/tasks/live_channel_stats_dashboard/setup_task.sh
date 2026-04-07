#!/bin/bash
set -e
echo "=== Setting up Live Channel Stats Dashboard task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is writable
mkdir -p /var/www/html
chmod 777 /var/www/html
echo "Created /var/www/html with 777 permissions"

# Helper to create a simulation channel via API
create_sim_channel() {
    local name="$1"
    local port="$2"
    local id=$(uuidgen)
    
    # Simple channel: TCP Listener -> Javascript Writer (doing nothing)
    # XML structure minimal for import
    cat <<EOF > "/tmp/${name}.xml"
<channel version="4.5.0">
  <id>${id}</id>
  <name>${name}</name>
  <enabled>true</enabled>
  <sourceConnector version="4.5.0">
    <transportName>TCP Listener</transportName>
    <mode>SOURCE</mode>
    <enabled>true</enabled>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties/>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>${port}</port>
      </listenerConnectorProperties>
      <sourceConnectorProperties version="4.5.0">
        <responseVariable>None</responseVariable>
      </sourceConnectorProperties>
      <transmissionModeProperties class="com.mirth.connect.plugins.mllpmode.MLLPModeProperties" version="4.5.0">
        <pluginPointName>MLLP</pluginPointName>
        <startOfMessageBytes>0B</startOfMessageBytes>
        <endOfMessageBytes>1C0D</endOfMessageBytes>
        <useMLLPv2>false</useMLLPv2>
        <ackBytes>06</ackBytes>
        <nackBytes>15</nackBytes>
        <maxRetries>0</maxRetries>
      </transmissionModeProperties>
      <serverMode>true</serverMode>
      <reconnectInterval>5000</reconnectInterval>
      <receiveTimeout>0</receiveTimeout>
      <bufferSize>65536</bufferSize>
      <maxConnections>10</maxConnections>
      <keepConnectionOpen>true</keepConnectionOpen>
      <dataTypeBinary>false</dataTypeBinary>
      <charsetEncoding>DEFAULT_ENCODING</charsetEncoding>
      <respondOnNewConnection>0</respondOnNewConnection>
    </properties>
    <transformer version="4.5.0">
      <elements/>
      <inboundDataType>HL7V2</inboundDataType>
      <outboundDataType>HL7V2</outboundDataType>
    </transformer>
  </sourceConnector>
  <destinationConnectors>
    <connector version="4.5.0">
      <name>Sink</name>
      <transportName>JavaScript Writer</transportName>
      <mode>DESTINATION</mode>
      <enabled>true</enabled>
      <properties class="com.mirth.connect.connectors.js.JavaScriptDispatcherProperties" version="4.5.0">
        <pluginProperties/>
        <destinationConnectorProperties version="4.5.0"/>
        <script>return;</script>
      </properties>
      <transformer version="4.5.0">
        <elements/>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
      </transformer>
    </connector>
  </destinationConnectors>
  <preprocessingScript>// Modify the message variable below to pre process data
return message;</preprocessingScript>
</channel>
EOF

    echo "Deploying channel: ${name}..."
    curl -sk -X POST -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Content-Type: application/xml" \
        -d @"/tmp/${name}.xml" \
        "https://localhost:8443/api/channels" > /dev/null
        
    # Deploy channels
    curl -sk -X POST -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/channels/_deploy" > /dev/null
}

# Wait for API to be ready
wait_for_api 60

# Create simulation channels
create_sim_channel "Sim_ADT_Inbound" "9001"
create_sim_channel "Sim_Lab_Results" "9002"

echo "Waiting for channels to start..."
sleep 10

# Inject some initial traffic (valid and invalid to create stats)
# Valid message
printf '\x0bMSH|^~\\&|SEND|FAC|REC|FAC|202301010000||ADT^A01|MSG001|P|2.3\r\x1c\x0d' | nc localhost 9001
# Error message (garbage) - MLLP reader might just reject or error
echo "GARBAGE DATA" | nc localhost 9001 || true

printf '\x0bMSH|^~\\&|LAB|FAC|REC|FAC|202301010000||ORU^R01|MSG002|P|2.3\r\x1c\x0d' | nc localhost 9002

echo "Initial traffic injected."

# Open a terminal for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Ops Dashboard Task"
echo "============================================"
echo ""
echo "TASK: Build a dashboard channel that monitors other channels."
echo ""
echo "API Endpoint: https://localhost:8443/api/channels/statistics"
echo "Creds: admin / admin"
echo "Headers: X-Requested-With: OpenAPI, Accept: application/json"
echo ""
echo "Goal: Write HTML table to /var/www/html/dashboard.html"
echo "Update Interval: 30 seconds"
echo ""
echo "Simulated Channels (already running):"
echo " - Sim_ADT_Inbound (Port 9001)"
echo " - Sim_Lab_Results (Port 9002)"
echo ""
echo "Tools: curl, python3, firefox"
echo "============================================"
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="