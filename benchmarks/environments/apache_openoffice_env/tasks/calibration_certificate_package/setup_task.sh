#!/bin/bash
set -e
echo "=== Setting up calibration_certificate_package task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents

# Remove any previous task artifacts
rm -f /home/ga/Documents/CalCert_Package_SCP_2024_0147.odt 2>/dev/null || true
rm -f /home/ga/Documents/calibration_data.json 2>/dev/null || true

# Generate the calibration data JSON file
cat > /home/ga/Documents/calibration_data.json << 'JSONEOF'
{
  "package_info": {
    "package_number": "SCP-2024-0147",
    "issue_date": "2024-11-20",
    "prepared_by": "Marcus Okafor, Calibration Technician III",
    "reviewed_by": "Dr. Yolanda Sims, Quality Manager",
    "lab_name": "TruePoint Calibration Labs, LLC",
    "lab_address": "7120 Statesville Road, Suite 300, Charlotte, NC 28269",
    "lab_phone": "(704) 555-0193",
    "lab_email": "certificates@truepointcal.com",
    "accreditation": "A2LA Certificate #4521",
    "accreditation_scope": "ISO/IEC 17025:2017 — Electrical, Temperature, Pressure, Mass"
  },
  "client": {
    "name": "Southeastern Chemical Processing, Inc.",
    "address": "2800 Industrial Park Drive, Greenville, SC 29605",
    "contact_name": "Thomas Bridwell",
    "contact_title": "Maintenance Manager",
    "contact_phone": "(864) 555-0247",
    "purchase_order": "PO-2024-08832"
  },
  "instruments": [
    {
      "certificate_number": "TC-2024-11-3891",
      "description": "Digital Multimeter",
      "manufacturer": "Fluke",
      "model": "87V",
      "serial_number": "27340089",
      "asset_tag": "SCP-EI-0234",
      "calibration_date": "2024-11-18",
      "next_due_date": "2025-11-18",
      "calibration_interval_months": 12,
      "location_calibrated": "TruePoint Lab — Bench 4",
      "condition_received": "Functional, no visible damage",
      "result": "PASS",
      "environmental_conditions": {
        "temperature_C": 23.1,
        "humidity_percent": 42,
        "barometric_pressure_kPa": 101.1
      },
      "reference_standard": {
        "description": "Multi-Product Calibrator",
        "manufacturer": "Fluke",
        "model": "5520A",
        "serial_number": "9876543",
        "cal_due_date": "2025-04-15",
        "nist_traceable": true
      },
      "measurement_data": {
        "parameter": "DC Voltage",
        "unit": "V",
        "points": [
          {"nominal": 0.0, "as_found": 0.0001, "as_left": 0.0001, "tolerance": 0.003, "status": "PASS"},
          {"nominal": 1.0, "as_found": 0.9998, "as_left": 0.9998, "tolerance": 0.005, "status": "PASS"},
          {"nominal": 10.0, "as_found": 10.003, "as_left": 10.003, "tolerance": 0.04, "status": "PASS"},
          {"nominal": 100.0, "as_found": 100.02, "as_left": 100.02, "tolerance": 0.4, "status": "PASS"},
          {"nominal": 1000.0, "as_found": 999.8, "as_left": 999.8, "tolerance": 4.0, "status": "PASS"}
        ],
        "expanded_uncertainty": "±(0.05% of reading + 0.005% of range), k=2, 95% confidence"
      },
      "measurement_data_2": {
        "parameter": "Resistance",
        "unit": "Ω",
        "points": [
          {"nominal": 100.0, "as_found": 100.01, "as_left": 100.01, "tolerance": 0.5, "status": "PASS"},
          {"nominal": 1000.0, "as_found": 999.7, "as_left": 999.7, "tolerance": 5.0, "status": "PASS"},
          {"nominal": 10000.0, "as_found": 10004, "as_left": 10004, "tolerance": 50, "status": "PASS"},
          {"nominal": 100000.0, "as_found": 99980, "as_left": 99980, "tolerance": 500, "status": "PASS"},
          {"nominal": 1000000.0, "as_found": 1000200, "as_left": 1000200, "tolerance": 5000, "status": "PASS"}
        ],
        "expanded_uncertainty": "±(0.1% of reading + 0.01% of range), k=2, 95% confidence"
      }
    },
    {
      "certificate_number": "TC-2024-11-3892",
      "description": "Thermocouple Thermometer",
      "manufacturer": "Omega",
      "model": "HH42A",
      "serial_number": "TC-88712",
      "asset_tag": "SCP-TH-0089",
      "calibration_date": "2024-11-18",
      "next_due_date": "2025-11-18",
      "calibration_interval_months": 12,
      "location_calibrated": "TruePoint Lab — Temperature Bay",
      "condition_received": "Functional, Type K probe included",
      "result": "PASS",
      "environmental_conditions": {
        "temperature_C": 22.8,
        "humidity_percent": 44,
        "barometric_pressure_kPa": 101.0
      },
      "reference_standard": {
        "description": "Metrology Well Temperature Calibrator",
        "manufacturer": "Hart Scientific (Fluke)",
        "model": "9170",
        "serial_number": "A45201",
        "cal_due_date": "2025-06-30",
        "nist_traceable": true
      },
      "measurement_data": {
        "parameter": "Temperature",
        "unit": "°C",
        "points": [
          {"nominal": -40.0, "as_found": -39.8, "as_left": -39.8, "tolerance": 1.0, "status": "PASS"},
          {"nominal": 0.0, "as_found": 0.1, "as_left": 0.1, "tolerance": 1.0, "status": "PASS"},
          {"nominal": 100.0, "as_found": 100.3, "as_left": 100.3, "tolerance": 1.0, "status": "PASS"},
          {"nominal": 250.0, "as_found": 250.6, "as_left": 250.6, "tolerance": 1.5, "status": "PASS"},
          {"nominal": 500.0, "as_found": 501.1, "as_left": 501.1, "tolerance": 2.0, "status": "PASS"}
        ],
        "expanded_uncertainty": "±0.3 °C (at k=2, 95% confidence level) for range 0–500 °C"
      }
    },
    {
      "certificate_number": "TC-2024-11-3893",
      "description": "Pressure Gauge",
      "manufacturer": "Ashcroft",
      "model": "2089",
      "serial_number": "PG-445601",
      "asset_tag": "SCP-PG-0156",
      "range": "0–300 PSI",
      "calibration_date": "2024-11-19",
      "next_due_date": "2025-11-19",
      "calibration_interval_months": 12,
      "location_calibrated": "TruePoint Lab — Pressure Bench",
      "condition_received": "Functional, dial face clean, no zero error",
      "result": "PASS",
      "environmental_conditions": {
        "temperature_C": 23.0,
        "humidity_percent": 40,
        "barometric_pressure_kPa": 101.2
      },
      "reference_standard": {
        "description": "Pneumatic Deadweight Tester",
        "manufacturer": "Ametek",
        "model": "T-1",
        "serial_number": "DW-2290",
        "cal_due_date": "2025-03-22",
        "nist_traceable": true
      },
      "measurement_data": {
        "parameter": "Pressure (Ascending)",
        "unit": "PSI",
        "points": [
          {"nominal": 0, "as_found": 0.0, "as_left": 0.0, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 75, "as_found": 75.2, "as_left": 75.2, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 150, "as_found": 150.1, "as_left": 150.1, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 225, "as_found": 224.8, "as_left": 224.8, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 300, "as_found": 300.3, "as_left": 300.3, "tolerance": 0.75, "status": "PASS"}
        ],
        "expanded_uncertainty": "±0.1% of span (±0.3 PSI), k=2, 95% confidence"
      },
      "measurement_data_2": {
        "parameter": "Pressure (Descending)",
        "unit": "PSI",
        "points": [
          {"nominal": 300, "as_found": 300.4, "as_left": 300.4, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 225, "as_found": 225.1, "as_left": 225.1, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 150, "as_found": 150.3, "as_left": 150.3, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 75, "as_found": 75.4, "as_left": 75.4, "tolerance": 0.75, "status": "PASS"},
          {"nominal": 0, "as_found": 0.1, "as_left": 0.1, "tolerance": 0.75, "status": "PASS"}
        ],
        "expanded_uncertainty": "±0.1% of span (±0.3 PSI), k=2, 95% confidence"
      }
    },
    {
      "certificate_number": "TC-2024-11-3894",
      "description": "Precision Balance",
      "manufacturer": "Mettler Toledo",
      "model": "ML3002E",
      "serial_number": "B912004567",
      "asset_tag": "SCP-BA-0312",
      "capacity": "3200 g",
      "readability": "0.01 g",
      "calibration_date": "2024-11-19",
      "next_due_date": "2025-11-19",
      "calibration_interval_months": 12,
      "location_calibrated": "TruePoint Lab — Mass Metrology Room",
      "condition_received": "Functional, level bubble centered, draft shield intact",
      "result": "PASS",
      "environmental_conditions": {
        "temperature_C": 22.5,
        "humidity_percent": 38,
        "barometric_pressure_kPa": 101.3
      },
      "reference_standard": {
        "description": "UltraClass Stainless Steel Weight Set, ASTM E617 Class 1",
        "manufacturer": "Troemner",
        "model": "UltraClass",
        "serial_number": "UC-334721",
        "cal_due_date": "2025-08-10",
        "nist_traceable": true
      },
      "measurement_data": {
        "parameter": "Mass",
        "unit": "g",
        "points": [
          {"nominal": 0.0, "as_found": 0.00, "as_left": 0.00, "tolerance": 0.02, "status": "PASS"},
          {"nominal": 100.0, "as_found": 100.01, "as_left": 100.01, "tolerance": 0.03, "status": "PASS"},
          {"nominal": 500.0, "as_found": 500.00, "as_left": 500.00, "tolerance": 0.05, "status": "PASS"},
          {"nominal": 1000.0, "as_found": 1000.02, "as_left": 1000.02, "tolerance": 0.10, "status": "PASS"},
          {"nominal": 3000.0, "as_found": 3000.01, "as_left": 3000.01, "tolerance": 0.20, "status": "PASS"}
        ],
        "expanded_uncertainty": "±0.02 g (at k=2, 95% confidence level) for range 0–3200 g",
        "repeatability_test": {
          "test_weight_g": 1000.0,
          "readings": [1000.02, 1000.01, 1000.02, 1000.01, 1000.02],
          "std_deviation": 0.005,
          "acceptance_limit": 0.02,
          "status": "PASS"
        }
      }
    }
  ],
  "general_notes": [
    "All calibrations performed in accordance with TruePoint SOP-CAL-001 through SOP-CAL-004.",
    "Results reported apply only to the items calibrated and at the conditions stated.",
    "This certificate shall not be reproduced, except in full, without written approval from TruePoint Calibration Labs, LLC.",
    "Calibration results are traceable to the International System of Units (SI) through NIST."
  ]
}
JSONEOF

# Set ownership
chown ga:ga /home/ga/Documents/calibration_data.json
chmod 644 /home/ga/Documents/calibration_data.json

# Record initial state
echo "0" > /tmp/initial_file_exists
ls -la /home/ga/Documents/ > /tmp/initial_dir_state 2>&1 || true

# Kill any existing OpenOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create desktop shortcut for OpenOffice Writer to help the agent
if [ -d "/home/ga/Desktop" ] && [ -x "/opt/openoffice4/program/soffice" ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Launch OpenOffice Writer so it's ready for the agent
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "OpenOffice" 2>/dev/null || true

# Dismiss any startup dialogs (like "Welcome")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="