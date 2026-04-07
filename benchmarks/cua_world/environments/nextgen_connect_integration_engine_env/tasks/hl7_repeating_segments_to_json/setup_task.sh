#!/bin/bash
set -e
echo "=== Setting up Task: Extract Repeating HL7 Segments to JSON Array ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare directories
echo "Preparing directories..."
mkdir -p /home/ga/json_out
chmod 777 /home/ga/json_out
mkdir -p /home/ga/sample_data
chmod 777 /home/ga/sample_data

# Clean up any previous run artifacts
rm -f /home/ga/json_out/*.json

# 2. Create realistic sample HL7 file with multiple NK1 segments
echo "Creating sample data..."
cat > /home/ga/sample_data/sample_adt_nk1.hl7 << 'EOF'
MSH|^~\&|EPIC|HOSPITAL|CONNECT|PORTAL|20240315103000||ADT^A01|MSG00001|P|2.3
EVN|A01|20240315103000
PID|1||PT89455^^^MRN||WILLIAMS^SARAH^J||19850101|F|||123 MAIN ST^^ANYTOWN^CA^90210
NK1|1|WILLIAMS^MICHAEL|HUSB
NK1|2|JONES^MARY|MOTHER
NK1|3|WILLIAMS^THOMAS|SON
PV1|1|I|ICU^101^A||||1234^DOC^MAIN|||||||||||V1001
EOF
chown ga:ga /home/ga/sample_data/sample_adt_nk1.hl7

# 3. Record initial state
date +%s > /tmp/task_start_time.txt
get_channel_count > /tmp/initial_channel_count.txt

# 4. Open Terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Repeating Segments Task"
echo "============================================"
echo ""
echo "GOAL: Convert HL7 NK1 segments to JSON array"
echo ""
echo "1. Create channel: NK1_to_JSON"
echo "2. Source: TCP Listener on Port 6661 (MLLP)"
echo "3. Destination: File Writer to /home/ga/json_out/"
echo "   Filename: \${patientId}_contacts.json"
echo ""
echo "TRANSFORMATION REQUIREMENT:"
echo "   Iterate over ALL NK1 segments."
echo "   Output JSON format:"
echo "   {"
echo "     \"patientId\": \"...\", "
echo "     \"contacts\": ["
echo "       {\"name\": \"Family, Given\", \"relationship\": \"...\"},"
echo "       ..."
echo "     ]"
echo "   }"
echo ""
echo "Sample Data: /home/ga/sample_data/sample_adt_nk1.hl7"
echo ""
echo "API: https://localhost:8443/api (admin/admin)"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

# 5. Ensure Firefox is open
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="