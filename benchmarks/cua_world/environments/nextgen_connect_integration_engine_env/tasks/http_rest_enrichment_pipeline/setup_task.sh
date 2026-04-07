#!/bin/bash
echo "=== Setting up HTTP REST Enrichment Pipeline task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure output directory does not exist or is empty
rm -rf /tmp/enriched_output
mkdir -p /tmp/enriched_output
chmod 777 /tmp/enriched_output

# Create a sample HL7 file for the agent to use for testing
# Zip code 10001 (EAST)
echo -e "MSH|^~\\&|SEND|FACILITY|REC|FAC|20240101000000||ADT^A01|MSG001|P|2.5\rPID|1||12345^^^MRN||DOE^JOHN||19800101|M|||123 MAIN ST^^NEW YORK^NY^10001|||||||" > /home/ga/test_east.hl7
# Zip code 90210 (WEST)
echo -e "MSH|^~\\&|SEND|FACILITY|REC|FAC|20240101000000||ADT^A01|MSG002|P|2.5\rPID|1||67890^^^MRN||SMITH^JANE||19800101|F|||456 PALM DR^^BEVERLY HILLS^CA^90210|||||||" > /home/ga/test_west.hl7

chown ga:ga /home/ga/test_east.hl7 /home/ga/test_west.hl7

# Open a terminal window for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "========================================================="
echo " NextGen Connect - HTTP REST Enrichment Pipeline Task"
echo "========================================================="
echo ""
echo "GOAL: Build a 2-channel pipeline."
echo ""
echo "1. Mock Service (Port 6666, HTTP):"
echo "   - Input: ?zip=12345"
echo "   - Output: JSON {\"region\": \"EAST\"} or \"WEST\""
echo ""
echo "2. Enricher (Port 6661, TCP/MLLP, HL7v2):"
echo "   - Read PID.11.5 (Zip)"
echo "   - Call Mock Service"
echo "   - Write Region to PID.11.9"
echo "   - Save to /tmp/enriched_output/"
echo ""
echo "Test files provided in /home/ga/:"
echo "   - test_east.hl7 (Zip 10001 -> Expect EAST)"
echo "   - test_west.hl7 (Zip 90210 -> Expect WEST)"
echo ""
echo "Tools: curl, nc, docker"
echo "API: https://localhost:8443/api (admin/admin)"
echo "     Header: X-Requested-With: OpenAPI"
echo "========================================================="
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="