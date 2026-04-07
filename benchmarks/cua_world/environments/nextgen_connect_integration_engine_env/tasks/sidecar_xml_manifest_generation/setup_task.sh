#!/bin/bash
echo "=== Setting up sidecar_xml_manifest_generation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory does NOT exist (agent should create it or channel will)
# or we create it empty to avoid permission issues, but let's clear it
mkdir -p /home/ga/archive_drop
rm -f /home/ga/archive_drop/*
chown -R ga:ga /home/ga/archive_drop
chmod 777 /home/ga/archive_drop

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Wait for NextGen Connect API
wait_for_api 60

# Open a terminal window with instructions for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - XML Sidecar Generation"
echo "============================================"
echo ""
echo "TASK: Create channel \"Document_Archive_Feed\""
echo "  - Input: TCP Port 6661 (HL7)"
echo "  - Output Dir: /home/ga/archive_drop/"
echo ""
echo "  - Destination 1: adt-{MESSAGEID}.hl7 (Raw HL7)"
echo "  - Destination 2: adt-{MESSAGEID}.xml (XML Manifest)"
echo ""
echo "XML Requirements:"
echo "  - Convert EVN.2 date to ISO 8601 (YYYY-MM-DDTHH:MM:SS)"
echo "  - <OriginalFile> tag must match the HL7 filename"
echo ""
echo "REST API: https://localhost:8443/api"
echo "  Credentials: admin / admin"
echo "  Header: X-Requested-With: OpenAPI"
echo ""
echo "Web Dashboard: https://localhost:8443"
echo ""
echo "Useful tools: date, xmllint"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

# Focus the terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="