#!/bin/bash
set -e
echo "=== Setting up XML to HL7 Lab Transformation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure NextGen Connect container is running
if ! docker ps | grep -q "nextgen-connect"; then
    echo "Error: NextGen Connect container not running"
    exit 1
fi

# Create required directories inside the container
echo "Creating data directories in container..."
docker exec nextgen-connect mkdir -p /opt/mirthdata/xml_in
docker exec nextgen-connect mkdir -p /opt/mirthdata/hl7_out
docker exec nextgen-connect mkdir -p /opt/mirthdata/processed
docker exec nextgen-connect chown -R connect:connect /opt/mirthdata

# Create the sample XML file
echo "Creating sample data..."
cat > /tmp/sample_cbc.xml << 'EOF'
<LabResult>
    <Header>
        <MessageID>MSG-2024-001</MessageID>
        <DateTime>20240315103000</DateTime>
        <SendingApp>HEMA_ANALYZER</SendingApp>
    </Header>
    <Patient>
        <ID>PT45922</ID>
        <LastName>SMITH</LastName>
        <FirstName>JENNIFER</FirstName>
        <DOB>1982-07-15</DOB>
        <Gender>F</Gender>
    </Patient>
    <Order>
        <ID>ORD-9921</ID>
        <TestCode>CBC</TestCode>
        <TestName>Complete Blood Count</TestName>
        <Analytes>
            <Analyte>
                <Name>WBC</Name>
                <Value>7.2</Value>
                <Units>10*3/uL</Units>
                <Range>4.0-10.0</Range>
                <Flag>N</Flag>
            </Analyte>
            <Analyte>
                <Name>RBC</Name>
                <Value>4.10</Value>
                <Units>10*6/uL</Units>
                <Range>3.90-5.20</Range>
                <Flag>N</Flag>
            </Analyte>
            <Analyte>
                <Name>HGB</Name>
                <Value>13.5</Value>
                <Units>g/dL</Units>
                <Range>12.0-15.5</Range>
                <Flag>N</Flag>
            </Analyte>
            <Analyte>
                <Name>HCT</Name>
                <Value>41.0</Value>
                <Units>%</Units>
                <Range>37.0-47.0</Range>
                <Flag>N</Flag>
            </Analyte>
            <Analyte>
                <Name>PLT</Name>
                <Value>250</Value>
                <Units>10*3/uL</Units>
                <Range>150-450</Range>
                <Flag>N</Flag>
            </Analyte>
        </Analytes>
    </Order>
</LabResult>
EOF

# Copy sample file into container
docker cp /tmp/sample_cbc.xml nextgen-connect:/opt/mirthdata/xml_in/sample_cbc.xml

# Also put a copy in ga's home for reference
cp /tmp/sample_cbc.xml /home/ga/sample_cbc.xml
chown ga:ga /home/ga/sample_cbc.xml

# Record initial file count in output directory (should be 0)
docker exec nextgen-connect ls -1 /opt/mirthdata/hl7_out/ | wc -l > /tmp/initial_file_count.txt

# Ensure Firefox is open to the dashboard
if ! pgrep -f firefox > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Sample data located at: /opt/mirthdata/xml_in/sample_cbc.xml"
echo "Expected output directory: /opt/mirthdata/hl7_out/"