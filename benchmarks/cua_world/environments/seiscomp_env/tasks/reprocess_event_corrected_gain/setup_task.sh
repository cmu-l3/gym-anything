#!/bin/bash
set -e
echo "=== Setting up reprocess_event_corrected_gain task ==="

source /workspace/scripts/task_utils.sh

# Record task start time with a small offset
echo $(($(date +%s) - 2)) > /tmp/task_start_time.txt

# 1. Ensure SeisComP services are running
ensure_scmaster_running
sleep 2

# 2. Generate the "Corrected" Inventory File
mkdir -p /home/ga/Documents
cat > /tmp/create_scml.py << 'EOF'
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('/home/ga/seiscomp/etc/inventory/ge_stations.xml')
    root = tree.getroot()
    ns = root.tag.split('}')[0] + '}' if '}' in root.tag else ''

    # Update the gain for GE.GSI
    for station in root.iter(f'{ns}station'):
        if station.get('code') == 'GSI':
            for gain in station.iter(f'{ns}gain'):
                for val in gain.iter(f'{ns}value'):
                    try:
                        orig = float(val.text)
                        val.text = str(orig * 2.0)
                    except:
                        pass

    tree.write('/home/ga/Documents/GSI_corrected.scml', xml_declaration=True, encoding='utf-8')
except Exception as e:
    print(f"Error: {e}")
EOF

su - ga -c "python3 /tmp/create_scml.py"
chown ga:ga /home/ga/Documents/GSI_corrected.scml

# 3. Find Event ID and Record Initial Magnitude
EVENT_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT publicID FROM Event LIMIT 1;" 2>/dev/null)

echo "$EVENT_ID" > /tmp/event_id.txt

if [ -n "$EVENT_ID" ]; then
    INITIAL_MAG=$(mysql -u sysop -psysop seiscomp -N -e "SELECT magnitude_value FROM Magnitude WHERE publicID = (SELECT preferredMagnitudeID FROM Event WHERE publicID = '$EVENT_ID');" 2>/dev/null | head -1)
    echo "$INITIAL_MAG" > /tmp/initial_mag.txt
else
    echo "0" > /tmp/initial_mag.txt
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="