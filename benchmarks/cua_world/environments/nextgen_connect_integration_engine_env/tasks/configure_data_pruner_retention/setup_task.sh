#!/bin/bash
set -e
echo "=== Setting up Data Pruner Configuration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for API to be ready
echo "Waiting for NextGen Connect API..."
wait_for_api 120

# Define Channel XML templates (Minimal TCP Listener)
# We use Python to generate the XML to ensure uniqueness and correct structure
cat > /tmp/create_channels.py << 'EOF'
import sys
import uuid
import time

def get_channel_xml(name, port, description):
    channel_id = str(uuid.uuid4())
    return f"""<channel version="4.5.0">
  <id>{channel_id}</id>
  <nextMetaDataId>2</nextMetaDataId>
  <name>{name}</name>
  <description>{description}</description>
  <revision>1</revision>
  <sourceConnector version="4.5.0">
    <metaDataId>0</metaDataId>
    <name>sourceConnector</name>
    <properties class="com.mirth.connect.connectors.tcp.TcpReceiverProperties" version="4.5.0">
      <pluginProperties/>
      <listenerConnectorProperties version="4.5.0">
        <host>0.0.0.0</host>
        <port>{port}</port>
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
          <errorACKMessage>An Error Occurred Processing Message.</errorACKMessage>
          <rejectedACKCode>AR</rejectedACKCode>
          <rejectedACKMessage>Message Rejected.</rejectedACKMessage>
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
          <errorACKMessage>An Error Occurred Processing Message.</errorACKMessage>
          <rejectedACKCode>AR</rejectedACKCode>
          <rejectedACKMessage>Message Rejected.</rejectedACKMessage>
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
      <metaDataId>1</metaDataId>
      <name>Destination 1</name>
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
          <reattachAttachments>true</reattachAttachments>
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
          <batchProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2BatchProperties" version="4.5.0">
            <splitType>MSH_Segment</splitType>
            <batchScript></batchScript>
          </batchProperties>
          <responseGenerationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseGenerationProperties" version="4.5.0">
            <segmentDelimiter>\r</segmentDelimiter>
            <successfulACKCode>AA</successfulACKCode>
            <successfulACKMessage></successfulACKMessage>
            <errorACKCode>AE</errorACKCode>
            <errorACKMessage>An Error Occurred Processing Message.</errorACKMessage>
            <rejectedACKCode>AR</rejectedACKCode>
            <rejectedACKMessage>Message Rejected.</rejectedACKMessage>
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
            <errorACKMessage>An Error Occurred Processing Message.</errorACKMessage>
            <rejectedACKCode>AR</rejectedACKCode>
            <rejectedACKMessage>Message Rejected.</rejectedACKMessage>
            <msh15ACKAccept>false</msh15ACKAccept>
          </responseGenerationProperties>
          <responseValidationProperties class="com.mirth.connect.plugins.datatypes.hl7v2.HL7v2ResponseValidationProperties" version="4.5.0">
            <validateMessage>false</validateMessage>
            <originalMessageControlId>Destination_Encoded</originalMessageControlId>
            <originalIdMapVariable></originalIdMapVariable>
          </responseValidationProperties>
        </outboundProperties>
      </transformer>
      <responseTransformer version="4.5.0">
        <elements/>
        <inboundDataType>HL7V2</inboundDataType>
        <outboundDataType>HL7V2</outboundDataType>
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
    <storeAttachments>true</storeAttachments>
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
        <time>{int(time.time()*1000)}</time>
        <timezone>Etc/UTC</timezone>
      </lastModified>
      <pruningSettings>
        <archiveEnabled>false</archiveEnabled>
      </pruningSettings>
    </metadata>
  </exportData>
</channel>"""

print("Creating ADT Channel XML...")
with open("/tmp/adt_channel.xml", "w") as f:
    f.write(get_channel_xml("Regional_ADT_Feed", 6661, "Feed from Regional Hospital"))

print("Creating Lab Channel XML...")
with open("/tmp/lab_channel.xml", "w") as f:
    f.write(get_channel_xml("Lab_Orders_Interface", 6662, "Orders from LIS"))
EOF

# Execute Python script to generate XMLs
python3 /tmp/create_channels.py

# Create channels via API
echo "Creating channels via REST API..."
api_call "POST" "/channels" "$(cat /tmp/adt_channel.xml)"
api_call "POST" "/channels" "$(cat /tmp/lab_channel.xml)"

# Reset Data Pruner to default state (Disabled)
echo "Resetting Data Pruner configuration..."
DEFAULT_PROPS='<properties>
  <property name="enabled">false</property>
  <property name="pruningBlockSize">1000</property>
  <property name="archiveEnabled">false</property>
  <property name="includeAttachments">false</property>
  <property name="pruneEvents">false</property>
  <property name="pruneEventAge">30</property>
  <property name="scheduler.type">POLLING</property>
  <property name="scheduler.pollingType">TIME</property>
  <property name="scheduler.pollingHour">0</property>
  <property name="scheduler.pollingMinute">0</property>
</properties>'

api_call "PUT" "/extensions/Data%20Pruner/properties" "$DEFAULT_PROPS"

# Ensure Firefox is open to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="