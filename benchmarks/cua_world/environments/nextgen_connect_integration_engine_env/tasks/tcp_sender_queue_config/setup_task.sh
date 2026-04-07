#!/bin/bash
set -e
echo "=== Setting up tcp_sender_queue_config task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create sample HL7 message
cat > /home/ga/test_adt_a01.hl7 << 'EOF'
MSH|^~\&|ED_REG|ED_FACILITY|ADT_SYS|MAIN_HOSP|20240115143052||ADT^A01^ADT_A01|MSG00001|P|2.5.1|||AL|NE
EVN|A01|20240115143052|||JSMITH^Smith^John
PID|1||MRN12345^^^MAIN_HOSP^MR||DOE^JANE^A||19780523|F|||456 OAK AVE^^SPRINGFIELD^IL^62701||2175551234|2175555678||S|CAT|ACCT98765|||SSN987654321
PV1|1|E|ED^ROOM3^BED1^MAIN_HOSP||||DOC789^WILSON^ROBERT^J^^^MD|DOC456^CHEN^LISA^M^^^MD||EM|||||||DOC789^WILSON^ROBERT^J^^^MD|ER|VN112233|||||||||||||||||||MAIN_HOSP|||||20240115142500
NK1|1|DOE^JOHN^B|SPO|456 OAK AVE^^SPRINGFIELD^IL^62701|2175559876
IN1|1|BCBS001|BCBS_IL|BLUE CROSS BLUE SHIELD IL||||GROUP54321||||||20230101|20251231|||DOE^JANE^A|SELF|19780523|456 OAK AVE^^SPRINGFIELD^IL^62701
EOF
chown ga:ga /home/ga/test_adt_a01.hl7

# Wait for API to be ready
echo "Waiting for API..."
wait_for_api 60

# Check if Downstream_ADT_Receiver already exists, if not create it
# This simulates the destination system listening on 6665
if ! channel_exists "Downstream_ADT_Receiver"; then
    echo "Creating Downstream ADT Receiver channel on port 6665..."
    
    # Define channel XML for receiver
    # Uses TCP Listener on 6665 -> Channel Writer (Sink)
    RECEIVER_XML='<channel version="4.5.0">
  <name>Downstream_ADT_Receiver</name>
  <description>Simulated Downstream System</description>
  <enabled>true</enabled>
  <sourceConnector version="4.5.0">
    <transportName>TCP Listener</transportName>
    <mode>SOURCE</mode>
    <enabled>true</enabled>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties/>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>6665</port>
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
        <queueBufferSize>1000</queueBufferSize>
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
      </outboundProperties>
    </transformer>
    <filter version="4.5.0">
      <elements/>
    </filter>
  </sourceConnector>
  <destinationConnectors>
    <connector version="4.5.0">
      <metaDataId>1</metaDataId>
      <name>Sink</name>
      <properties class="com.mirth.connect.connectors.vm.VmDispatcherProperties" version="4.5.0">
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
          <threadAssignmentVariable></threadAssignmentVariable>
          <validateResponse>false</validateResponse>
          <resourceIds class="linked-hash-map">
            <entry>
              <string>Default Resource</string>
              <string>[Default Resource]</string>
            </entry>
          </resourceIds>
          <queueBufferSize>1000</queueBufferSize>
          <reattachContext>false</reattachContext>
        </destinationConnectorProperties>
        <channelId>none</channelId>
        <channelTemplate>${message.encodedData}</channelTemplate>
        <mapVariables/>
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
        </outboundProperties>
      </transformer>
      <responseTransformer version="4.5.0">
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
        </outboundProperties>
      </responseTransformer>
      <filter version="4.5.0">
        <elements/>
      </filter>
      <transportName>Channel Writer</transportName>
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
  <properties version="4.5.0">
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
  <exportData>
    <metadata>
      <enabled>true</enabled>
      <lastModified>
        <time>1700000000000</time>
        <timezone>Etc/UTC</timezone>
      </lastModified>
      <pruningSettings>
        <archiveEnabled>true</archiveEnabled>
        <pruneErroredMessages>false</pruneErroredMessages>
      </pruningSettings>
      <userId>1</userId>
    </metadata>
  </exportData>
</channel>'
    
    # Send to API to create channel
    api_call "POST" "/channels" "$RECEIVER_XML" > /dev/null
    
    # Get ID
    RECV_ID=$(get_channel_id "Downstream_ADT_Receiver")
    
    if [ -n "$RECV_ID" ]; then
        echo "Deploying Downstream ADT Receiver ($RECV_ID)..."
        api_call_json "POST" "/channels/$RECV_ID/_deploy" "" > /dev/null
    else
        echo "Failed to create receiver channel!"
    fi
fi

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure Firefox is open to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="