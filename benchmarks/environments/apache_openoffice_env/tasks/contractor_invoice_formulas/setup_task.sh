#!/bin/bash
echo "=== Setting up Contractor Invoice Formulas Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up previous run artifacts
rm -f /home/ga/Documents/GreenLeaf_Invoice_1024.odt 2>/dev/null || true
rm -f /home/ga/Documents/job_data.json 2>/dev/null || true

# Create the job data JSON file
cat > /home/ga/Documents/job_data.json << 'EOF'
{
  "company": {
    "name": "GreenLeaf Landscaping Services",
    "address": "4500 Skyline Blvd, Portland, OR 97229",
    "phone": "(503) 555-0199"
  },
  "client": {
    "name": "Mark & Sarah Henderson",
    "address": "8821 NW 13th Ave, Portland, OR 97209"
  },
  "invoice_details": {
    "number": "1024",
    "date": "2026-05-15",
    "tax_rate_percent": 5.5
  },
  "line_items": [
    {
      "description": "Installation Labor",
      "quantity": 32,
      "unit_price": 65.00
    },
    {
      "description": "Emerald Green Arborvitae (5 gal)",
      "quantity": 15,
      "unit_price": 45.00
    },
    {
      "description": "Hemlock Bark Mulch (cu yd)",
      "quantity": 8,
      "unit_price": 38.50
    },
    {
      "description": "Drip Irrigation Tubing (ft)",
      "quantity": 250,
      "unit_price": 0.45
    },
    {
      "description": "Debris Removal & Disposal",
      "quantity": 1,
      "unit_price": 175.00
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/job_data.json
chmod 644 /home/ga/Documents/job_data.json

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch OpenOffice Writer to a blank document
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "Writer window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file created at: /home/ga/Documents/job_data.json"