#!/bin/bash
# Setup script for agronomy_scouting_report task

echo "=== Setting up Agronomy Scouting Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/ValleyView_Alfalfa_Report_June2025.odt 2>/dev/null || true
rm -f /home/ga/Documents/field_data.json 2>/dev/null || true

# 3. Create the Field Data JSON file
cat > /home/ga/Documents/field_data.json << 'EOF'
{
  "report_date": "2025-06-15",
  "client": {
    "name": "Valley View Dairy",
    "contact": "Mike Miller"
  },
  "field": {
    "id": "Alfalfa-04",
    "crop": "Alfalfa",
    "stage": "Second Cutting - 12 inches",
    "acres": 45
  },
  "observations": [
    {
      "pest": "Potato Leafhopper",
      "scientific_name": "Empoasca fabae",
      "count_avg": "2.5 per sweep",
      "economic_threshold": "2.0 per sweep",
      "status": "ABOVE THRESHOLD"
    },
    {
      "pest": "Alfalfa Weevil",
      "count_avg": "0.1 per stem",
      "economic_threshold": "1.0 per stem",
      "status": "Below Threshold"
    }
  ],
  "recommendations": {
    "action_plan": "Chemical application recommended immediately due to leafhopper pressure.",
    "chemical": {
      "product_name": "Warrior II with Zeon Technology",
      "active_ingredient": "Lambda-cyhalothrin",
      "rate": "1.92 fl oz/acre",
      "phi_grazing": "7 days",
      "phi_harvest": "1 day"
    },
    "safety_data": {
      "restricted_entry_interval_rei": "24 hours",
      "ppe_required": "Coveralls, chemical-resistant gloves, protective eyewear"
    }
  }
}
EOF
chown ga:ga /home/ga/Documents/field_data.json
chmod 644 /home/ga/Documents/field_data.json

# 4. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenOffice Writer
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 5
fi

# 6. Wait for window and maximize
wait_for_window "OpenOffice Writer" 30
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file created at: /home/ga/Documents/field_data.json"