#!/bin/bash
echo "=== Exporting crossvalidate_event_db task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Dump the Ground Truth XML directly from the DB using scxmldump
su - ga -c "SEISCOMP_ROOT=/home/ga/seiscomp PATH=/home/ga/seiscomp/bin:\$PATH LD_LIBRARY_PATH=/home/ga/seiscomp/lib:\$LD_LIBRARY_PATH scxmldump -d mysql://sysop:sysop@localhost/seiscomp -f -o /tmp/gt_dump.xml" 2>/dev/null

# Parse the Ground Truth XML into a JSON format to provide verified parameters to the verifier
python3 << 'EOF'
import xml.etree.ElementTree as ET
import json
import re

try:
    with open('/tmp/gt_dump.xml', 'r') as f:
        xml_content = f.read()
    
    # Strip namespaces for hassle-free xpath selection
    xml_content = re.sub(r'\sxmlns="[^"]+"', '', xml_content, count=1)
    xml_content = re.sub(r'xmlns:[a-zA-Z0-9\-]+="[^"]+"', '', xml_content)
    root = ET.fromstring(xml_content)
    
    event = root.find('.//event')
    if event is not None:
        event_id = event.attrib.get('publicID', '')
        pref_org_elem = event.find('.//preferredOriginID')
        pref_org = pref_org_elem.text if pref_org_elem is not None else ''
        
        pref_mag_elem = event.find('.//preferredMagnitudeID')
        pref_mag = pref_mag_elem.text if pref_mag_elem is not None else ''
        
        org = root.find(f".//origin[@publicID='{pref_org}']") if pref_org else None
        lat = org.find('.//latitude/value').text if org is not None and org.find('.//latitude/value') is not None else '0'
        lon = org.find('.//longitude/value').text if org is not None and org.find('.//longitude/value') is not None else '0'
        depth = org.find('.//depth/value').text if org is not None and org.find('.//depth/value') is not None else '0'
        time_val = org.find('.//time/value').text if org is not None and org.find('.//time/value') is not None else ''
        
        mag = root.find(f".//magnitude[@publicID='{pref_mag}']") if pref_mag else None
        mag_val = mag.find('.//magnitude/value').text if mag is not None and mag.find('.//magnitude/value') is not None else '0'
        mag_type = mag.find('.//type').text if mag is not None and mag.find('.//type') is not None else ''
        
        gt = {
            "event_id": event_id,
            "origin_id": pref_org,
            "magnitude_id": pref_mag,
            "latitude": float(lat),
            "longitude": float(lon),
            "depth": float(depth),
            "time": time_val,
            "magnitude_value": float(mag_val),
            "magnitude_type": mag_type
        }
    else:
        gt = {}
except Exception as e:
    gt = {"error": str(e)}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
EOF

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Determine file presence and timestamps
REPORT_FILE="/home/ga/earthquake_validation_report.txt"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    else
        REPORT_CREATED="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_MTIME="0"
    REPORT_SIZE="0"
    REPORT_CREATED="false"
fi

XML_FILE="/home/ga/event_dump.xml"
if [ -f "$XML_FILE" ]; then
    XML_EXISTS="true"
    XML_MTIME=$(stat -c %Y "$XML_FILE" 2>/dev/null || echo "0")
    XML_SIZE=$(stat -c %s "$XML_FILE" 2>/dev/null || echo "0")
    if [ "$XML_MTIME" -gt "$TASK_START" ]; then
        XML_CREATED="true"
    else
        XML_CREATED="false"
    fi
else
    XML_EXISTS="false"
    XML_MTIME="0"
    XML_SIZE="0"
    XML_CREATED="false"
fi

take_screenshot /tmp/task_end.png 2>/dev/null || true

# Assemble aggregated payload for verification logic (no DB queries needed in python verifier)
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED,
    "report_size": $REPORT_SIZE,
    "xml_exists": $XML_EXISTS,
    "xml_created_during_task": $XML_CREATED,
    "xml_size": $XML_SIZE,
    "ground_truth": $(cat /tmp/ground_truth.json 2>/dev/null || echo "{}")
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="