#!/bin/bash
echo "=== Setting up Conference Schedule Grid Task ==="
source /workspace/scripts/task_utils.sh

# 1. Prepare User Environment
sudo -u ga mkdir -p /home/ga/Documents
# Clean up any previous attempts
rm -f /home/ga/Documents/Summit_Schedule_2025.odt 2>/dev/null || true

# 2. Create Real Data File (schedule_data.json)
cat > /home/ga/Documents/schedule_data.json << 'EOF'
{
  "conference": "Midwest Digital Health Summit 2025",
  "date": "October 15, 2025",
  "location": "Minneapolis Convention Center",
  "tracks": {
    "A": "Clinical Innovation",
    "B": "Health IT & Data",
    "C": "Policy & Compliance"
  },
  "schedule": [
    {
      "time": "08:00 - 09:00",
      "type": "plenary",
      "title": "Registration & Breakfast"
    },
    {
      "time": "09:00 - 10:15",
      "type": "plenary",
      "title": "Opening Keynote: The Future of Interoperability - Dr. Sarah Chen"
    },
    {
      "time": "10:30 - 11:45",
      "type": "concurrent",
      "sessions": {
        "A": "AI in Radiology: Early Detection Models",
        "B": "FHIR Standards Update v5.0",
        "C": "HIPAA Compliance in the Cloud Era"
      }
    },
    {
      "time": "12:00 - 13:30",
      "type": "plenary",
      "title": "Networking Lunch"
    },
    {
      "time": "13:30 - 14:45",
      "type": "concurrent",
      "sessions": {
        "A": "Telehealth Workflows Post-Pandemic",
        "B": "Data Lakes vs. Warehouses in Healthcare",
        "C": "Regulatory Landscape for Medical Devices"
      }
    },
    {
      "time": "15:00 - 16:00",
      "type": "plenary",
      "title": "Closing Panel: Patient Advocacy"
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/schedule_data.json
chmod 644 /home/ga/Documents/schedule_data.json

# 3. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# 4. Launch Application (OpenOffice Writer)
# The task description says "OpenOffice Writer is open (blank document)"
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    wait_for_window "OpenOffice Writer" 30
fi

# 5. Maximize Window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file created: /home/ga/Documents/schedule_data.json"
echo "Target output: /home/ga/Documents/Summit_Schedule_2025.odt"