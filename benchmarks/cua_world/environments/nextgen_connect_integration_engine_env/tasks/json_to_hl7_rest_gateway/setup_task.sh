#!/bin/bash
echo "=== Setting up JSON to HL7 REST Gateway task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists inside the container (agent needs to write here)
echo "Creating output directory in container..."
docker exec nextgen-connect mkdir -p /tmp/hl7_output
docker exec nextgen-connect chmod 777 /tmp/hl7_output

# Create a sample JSON file for the agent to use
cat > /home/ga/sample_registration.json <<EOF
{
  "patient": {
    "mrn": "MRN-2024-78432",
    "lastName": "Rodriguez",
    "firstName": "Elena",
    "dateOfBirth": "1985-07-14",
    "sex": "F",
    "address": {
      "street": "2847 Maple Drive",
      "city": "Rochester",
      "state": "MN",
      "zip": "55901"
    },
    "phone": "507-555-0198"
  },
  "visit": {
    "visitNumber": "V-20240815-001",
    "admitDateTime": "20240815143000",
    "patientClass": "O",
    "attendingDoctor": {
      "id": "NPI1234567890",
      "lastName": "Chen",
      "firstName": "David"
    }
  }
}
EOF
chown ga:ga /home/ga/sample_registration.json

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Open a terminal with helpful info
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "========================================================"
echo " NextGen Connect - JSON to HL7 Gateway Task"
echo "========================================================"
echo ""
echo "Goal: Create a channel \"JSON_to_HL7_Gateway\""
echo "  - Source: HTTP Listener (Port 6661)"
echo "  - Transform: JSON -> HL7v2 ADT^A04"
echo "  - Destination: File Writer (/tmp/hl7_output/)"
echo ""
echo "Sample JSON payload available at:"
echo "  /home/ga/sample_registration.json"
echo ""
echo "Test your channel:"
echo "  curl -X POST -H \"Content-Type: application/json\" \\"
echo "       -d @/home/ga/sample_registration.json \\"
echo "       http://localhost:6661"
echo ""
echo "Check output inside container:"
echo "  docker exec nextgen-connect ls -l /tmp/hl7_output/"
echo ""
echo "NextGen Connect API: https://localhost:8443/api"
echo "  User: admin / Pass: admin"
echo "========================================================"
exec bash
' 2>/dev/null &

# Ensure Firefox is open to the dashboard
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="