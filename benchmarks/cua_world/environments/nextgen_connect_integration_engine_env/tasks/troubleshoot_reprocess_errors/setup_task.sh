#!/bin/bash
set -e
echo "=== Setting up Troubleshoot & Reprocess Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Define Directories and Permissions
OUTPUT_DIR="/home/ga/normalized_adt"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"
chmod 777 "$OUTPUT_DIR"

# 2. API Credentials
API_URL="https://localhost:8443/api"
CREDS="-u admin:admin"
HEADER="-H X-Requested-With:OpenAPI"

# 3. Create the Channel XML (with the BUG)
# The bug: `var fullState = stateMap[stateCode].toUpperCase();` crashes if stateCode not in map
cat > /tmp/channel.xml <<EOF
<channel version="4.5.0">
  <name>ADT_State_Normalizer</name>
  <description>Normalizes patient state codes to full names.</description>
  <enabled>true</enabled>
  <lastModified>
    <time>$(date +%s)000</time>
    <timezone>America/New_York</timezone>
  </lastModified>
  <revision>1</revision>
  <sourceConnector version="4.5.0">
    <name>sourceConnector</name>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties/>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>6661</port>
      </listenerConnectorProperties>
      <sourceClassName>com.mirth.connect.connectors.tcp.TcpReceiver</sourceClassName>
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
      <processBatch>false</processBatch>
      <dataType>HL7V2</dataType>
      <charsetEncoding>DEFAULT_ENCODING</charsetEncoding>
      <respondOnNewConnection>0</respondOnNewConnection>
      <responseAddress></responseAddress>
      <responsePort>0</responsePort>
    </properties>
    <transformer version="4.5.0">
      <elements/>
      <inboundDataType>HL7V2</inboundDataType>
      <outboundDataType>HL7V2</outboundDataType>
      <inboundProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties" version="4.5.0">
        <serializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties" version="4.5.0">
          <handleRepetitions>true</handleRepetitions>
          <handleSubcomponents>true</handleSubcomponents>
          <useStrictParser>false</useStrictParser>
          <useStrictValidation>false</useStrictValidation>
          <stripNamespaces>true</stripNamespaces>
          <segmentDelimiter>\r</segmentDelimiter>
          <convertLineBreaks>true</convertLineBreaks>
        </serializationProperties>
        <deserializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DeserializationProperties" version="4.5.0">
          <useStrictParser>false</useStrictParser>
          <useStrictValidation>false</useStrictValidation>
          <segmentDelimiter>\r</segmentDelimiter>
        </deserializationProperties>
        <batchProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2BatchProperties" version="4.5.0">
          <splitType>MSH_Segment</splitType>
          <batchScript></batchScript>
        </batchProperties>
        <responseGenerationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseGenerationProperties" version="4.5.0">
          <segmentDelimiter>\r</segmentDelimiter>
          <successfulACKCode>AA</successfulACKCode>
          <successfulACKMessage></successfulACKMessage>
          <errorACKCode>AE</errorACKCode>
          <errorACKMessage>An Error Occurred Processing Message</errorACKMessage>
          <rejectedACKCode>AR</rejectedACKCode>
          <rejectedACKMessage>Message Rejected</rejectedACKMessage>
          <msh15ACKAccept>false</msh15ACKAccept>
        </responseGenerationProperties>
        <responseValidationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseValidationProperties" version="4.5.0">
          <validateMessage>false</validateMessage>
          <originalMessageControlId>Destination_Encoded</originalMessageControlId>
          <originalIdMapVariable></originalIdMapVariable>
        </responseValidationProperties>
      </inboundProperties>
      <outboundProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties" version="4.5.0">
        <serializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties" version="4.5.0">
          <handleRepetitions>true</handleRepetitions>
          <handleSubcomponents>true</handleSubcomponents>
          <useStrictParser>false</useStrictParser>
          <useStrictValidation>false</useStrictValidation>
          <stripNamespaces>true</stripNamespaces>
          <segmentDelimiter>\r</segmentDelimiter>
          <convertLineBreaks>true</convertLineBreaks>
        </serializationProperties>
        <deserializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DeserializationProperties" version="4.5.0">
          <useStrictParser>false</useStrictParser>
          <useStrictValidation>false</useStrictValidation>
          <segmentDelimiter>\r</segmentDelimiter>
        </deserializationProperties>
        <batchProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2BatchProperties" version="4.5.0">
          <splitType>MSH_Segment</splitType>
          <batchScript></batchScript>
        </batchProperties>
        <responseGenerationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseGenerationProperties" version="4.5.0">
          <segmentDelimiter>\r</segmentDelimiter>
          <successfulACKCode>AA</successfulACKCode>
          <successfulACKMessage></successfulACKMessage>
          <errorACKCode>AE</errorACKCode>
          <errorACKMessage>An Error Occurred Processing Message</errorACKMessage>
          <rejectedACKCode>AR</rejectedACKCode>
          <rejectedACKMessage>Message Rejected</rejectedACKMessage>
          <msh15ACKAccept>false</msh15ACKAccept>
        </responseGenerationProperties>
        <responseValidationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseValidationProperties" version="4.5.0">
          <validateMessage>false</validateMessage>
          <originalMessageControlId>Destination_Encoded</originalMessageControlId>
          <originalIdMapVariable></originalIdMapVariable>
        </responseValidationProperties>
      </outboundProperties>
    </transformer>
    <filter version="4.5.0">
      <elements/>
    </filter>
    <transportName>TCP Listener</transportName>
    <mode>SOURCE</mode>
    <enabled>true</enabled>
    <waitForPrevious>true</waitForPrevious>
  </sourceConnector>
  <destinationConnectors>
    <connector version="4.5.0">
      <name>To_File</name>
      <properties class="com.mirth.connect.connectors.file.FileDispatcherProperties" version="4.5.0">
        <pluginProperties/>
        <destinationConnectorProperties version="4.5.0">
          <queueEnabled>false</queueEnabled>
          <sendFirst>false</sendFirst>
          <retryIntervalMillis>10000</retryIntervalMillis>
          <regenerateTemplate>false</regenerateTemplate>
          <retryCount>0</retryCount>
          <rotate>false</rotate>
          <includeFilterTransformer>false</includeFilterTransformer>
          <threadCount>1</threadCount>
          <validateResponse>false</validateResponse>
        </destinationConnectorProperties>
        <host>${OUTPUT_DIR}</host>
        <outputPattern>ADT_\${message.messageId}.hl7</outputPattern>
        <anonymous>true</anonymous>
        <append>false</append>
        <binary>false</binary>
        <charsetEncoding>DEFAULT_ENCODING</charsetEncoding>
        <template>\${message.encodedData}</template>
        <timeout>10000</timeout>
        <secure>true</secure>
        <passive>true</passive>
        <validateConnection>true</validateConnection>
        <errorOnExists>false</errorOnExists>
        <temporary>false</temporary>
        <scheme>FILE</scheme>
      </properties>
      <transformer version="4.5.0">
        <elements>
          <com.mirth.connect.plugins.javascriptstep.JavaScriptStep version="4.5.0">
            <name>Normalize State</name>
            <sequenceNumber>0</sequenceNumber>
            <enabled>true</enabled>
            <script>var stateMap = {
    &quot;CA&quot;: &quot;CALIFORNIA&quot;,
    &quot;NY&quot;: &quot;NEW YORK&quot;,
    &quot;TX&quot;: &quot;TEXAS&quot;,
    &quot;FL&quot;: &quot;FLORIDA&quot;,
    &quot;WA&quot;: &quot;WASHINGTON&quot;
};

// BUGGY CODE HERE
// Get state from PID-11.4
var stateCode = msg[&quot;PID&quot;][&quot;PID.11&quot;][&quot;PID.11.4&quot;].toString();

// This will crash if stateCode is not in map (returns undefined, then undefined.toUpperCase() throws)
// If stateCode is empty string, it also might fail depending on map lookup
var fullState = stateMap[stateCode].toUpperCase();

// Assign to temp variable for verifying
msg[&quot;PID&quot;][&quot;PID.11&quot;][&quot;PID.11.4&quot;] = fullState;</script>
          </com.mirth.connect.plugins.javascriptstep.JavaScriptStep>
        </elements>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
        <inboundProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties" version="4.5.0">
            <serializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties" version="4.5.0">
              <handleRepetitions>true</handleRepetitions>
              <handleSubcomponents>true</handleSubcomponents>
              <useStrictParser>false</useStrictParser>
              <useStrictValidation>false</useStrictValidation>
              <stripNamespaces>true</stripNamespaces>
              <segmentDelimiter>\r</segmentDelimiter>
              <convertLineBreaks>true</convertLineBreaks>
            </serializationProperties>
            <deserializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DeserializationProperties" version="4.5.0">
              <useStrictParser>false</useStrictParser>
              <useStrictValidation>false</useStrictValidation>
              <segmentDelimiter>\r</segmentDelimiter>
            </deserializationProperties>
            <batchProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2BatchProperties" version="4.5.0">
              <splitType>MSH_Segment</splitType>
              <batchScript></batchScript>
            </batchProperties>
            <responseGenerationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseGenerationProperties" version="4.5.0">
              <segmentDelimiter>\r</segmentDelimiter>
              <successfulACKCode>AA</successfulACKCode>
              <successfulACKMessage></successfulACKMessage>
              <errorACKCode>AE</errorACKCode>
              <errorACKMessage>An Error Occurred Processing Message</errorACKMessage>
              <rejectedACKCode>AR</rejectedACKCode>
              <rejectedACKMessage>Message Rejected</rejectedACKMessage>
              <msh15ACKAccept>false</msh15ACKAccept>
            </responseGenerationProperties>
            <responseValidationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseValidationProperties" version="4.5.0">
              <validateMessage>false</validateMessage>
              <originalMessageControlId>Destination_Encoded</originalMessageControlId>
              <originalIdMapVariable></originalIdMapVariable>
            </responseValidationProperties>
        </inboundProperties>
        <outboundProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties" version="4.5.0">
            <serializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2SerializationProperties" version="4.5.0">
              <handleRepetitions>true</handleRepetitions>
              <handleSubcomponents>true</handleSubcomponents>
              <useStrictParser>false</useStrictParser>
              <useStrictValidation>false</useStrictValidation>
              <stripNamespaces>true</stripNamespaces>
              <segmentDelimiter>\r</segmentDelimiter>
              <convertLineBreaks>true</convertLineBreaks>
            </serializationProperties>
            <deserializationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DeserializationProperties" version="4.5.0">
              <useStrictParser>false</useStrictParser>
              <useStrictValidation>false</useStrictValidation>
              <segmentDelimiter>\r</segmentDelimiter>
            </deserializationProperties>
            <batchProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2BatchProperties" version="4.5.0">
              <splitType>MSH_Segment</splitType>
              <batchScript></batchScript>
            </batchProperties>
            <responseGenerationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseGenerationProperties" version="4.5.0">
              <segmentDelimiter>\r</segmentDelimiter>
              <successfulACKCode>AA</successfulACKCode>
              <successfulACKMessage></successfulACKMessage>
              <errorACKCode>AE</errorACKCode>
              <errorACKMessage>An Error Occurred Processing Message</errorACKMessage>
              <rejectedACKCode>AR</rejectedACKCode>
              <rejectedACKMessage>Message Rejected</rejectedACKMessage>
              <msh15ACKAccept>false</msh15ACKAccept>
            </responseGenerationProperties>
            <responseValidationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseValidationProperties" version="4.5.0">
              <validateMessage>false</validateMessage>
              <originalMessageControlId>Destination_Encoded</originalMessageControlId>
              <originalIdMapVariable></originalIdMapVariable>
            </responseValidationProperties>
        </outboundProperties>
      </transformer>
      <filter version="4.5.0">
        <elements/>
      </filter>
      <transportName>File Writer</transportName>
      <mode>DESTINATION</mode>
      <enabled>true</enabled>
      <waitForPrevious>true</waitForPrevious>
    </connector>
  </destinationConnectors>
  <preprocessingScript>// Modify the message variable below to pre process data
return message;</preprocessingScript>
  <postprocessingScript>// This script executes once after a message has been processed
return;</postprocessingScript>
  <deployScript>// This script executes once when the channel is deployed
return;</deployScript>
  <undeployScript>// This script executes once when the channel is undeployed
return;</undeployScript>
  <properties>
    <clearGlobalChannelMap>true</clearGlobalChannelMap>
    <messageStorageMode>DEVELOPMENT</messageStorageMode>
    <encryptData>false</encryptData>
    <removeContentOnCompletion>false</removeContentOnCompletion>
    <removeOnlyFilteredOnCompletion>false</removeOnlyFilteredOnCompletion>
    <removeAttachmentsOnCompletion>false</removeAttachmentsOnCompletion>
    <initialState>STARTED</initialState>
    <storeAttachments>false</storeAttachments>
    <metaDataColumns>
      <metaDataColumn>
        <name>SOURCE</name>
        <type>STRING</type>
        <mappingName>mirth_source</mappingName>
      </metaDataColumn>
      <metaDataColumn>
        <name>TYPE</name>
        <type>STRING</type>
        <mappingName>mirth_type</mappingName>
      </metaDataColumn>
    </metaDataColumns>
    <attachmentProperties class="com.mirth.connect.donkey.model.channel.AttachmentProperties" version="4.5.0">
      <type>None</type>
      <properties/>
    </attachmentProperties>
    <resourceIds class="linked-hash-set">
      <string>Default Resource</string>
    </resourceIds>
  </properties>
</channel>
EOF

# 4. Import and Deploy Channel
echo "Importing Channel..."
curl -sk $CREDS $HEADER -X POST "$API_URL/channels" -d @/tmp/channel.xml -H "Content-Type: application/xml" > /tmp/import_resp.xml
CHANNEL_ID=$(grep -oP '<id>\K[^<]+' /tmp/import_resp.xml || echo "")

echo "Channel ID: $CHANNEL_ID"

echo "Deploying Channel..."
curl -sk $CREDS $HEADER -X POST "$API_URL/channels/_deploy" -d "[\"$CHANNEL_ID\"]" -H "Content-Type: application/json"

# Wait for channel to start
sleep 10

# 5. Generate and Send Data
# Function to send HL7
send_hl7() {
    local state="$1"
    local id="$2"
    # Construct minimal HL7 ADT
    # MSH|^~\&|SENDING|FAC|REC|FAC|202401010000||ADT^A01|MSG$id|P|2.5.1
    # PID|||PAT$id||TEST^PATIENT||19800101|M|||123 MAIN ST^^CITY^$state^90210
    local msg=$(printf "MSH|^~\\&|SENDING|FAC|REC|FAC|202401010000||ADT^A01|MSG%s|P|2.5.1\rPID|||PAT%s||TEST^PATIENT||19800101|M|||123 MAIN ST^^CITY^%s^90210\r" "$id" "$id" "$state")
    
    echo -n -e "\x0b$msg\x1c\r" | nc -w 1 localhost 6661
    sleep 0.2
}

echo "Sending 10 GOOD messages..."
for i in {1..10}; do
    send_hl7 "CA" "GOOD_$i"
done

echo "Sending 10 BAD messages..."
for i in {1..10}; do
    # Send "XX" which is not in the map
    send_hl7 "XX" "BAD_$i"
done

# Wait for processing
sleep 5

# Record task start time
date +%s > /tmp/task_start_time.txt

# Maximize Firefox for the agent
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
    sleep 5
fi
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "Setup complete. Channel should now have ~10 errors."