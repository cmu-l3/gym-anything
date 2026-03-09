#!/bin/bash
set -e

echo "=== Setting up Hardware Datasheet Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# 2. Clean up previous runs
rm -f /home/ga/Documents/SE9042_Datasheet.odt
rm -f /home/ga/Documents/SE9042_Datasheet.doc
rm -f /home/ga/Documents/SE9042_Datasheet.docx
rm -f /home/ga/Documents/product_specs.json

# 3. Create Input Data (product_specs.json)
cat > /home/ga/Documents/product_specs.json << 'EOF'
{
  "product_name": "SE-9042",
  "title": "Low-Power IoT Transceiver",
  "status": "Preliminary",
  "description": "The SE-9042 is a high-performance, low-power sub-GHz transceiver designed for use in a wide variety of wireless applications. It offers industry-leading sensitivity and low current consumption, making it ideal for battery-powered IoT devices.",
  "features": [
    "Frequency Range: 150 MHz to 960 MHz",
    "Sensitivity down to -148 dBm",
    "RX Current: 4.6 mA",
    "Data Rate: 0.1 kbps to 300 kbps",
    "Modulation: LoRa, FSK, GFSK, MSK",
    "Automatic RF Sense and CAD with ultra-fast AFC"
  ],
  "applications": [
    "Smart Metering",
    "Home Automation",
    "Agricultural Sensors",
    "Asset Tracking",
    "Wearable Devices"
  ],
  "electrical_characteristics": [
    {
      "parameter": "Supply Voltage",
      "min": "1.8 V",
      "typ": "3.3 V",
      "max": "3.7 V"
    },
    {
      "parameter": "Operating Temperature",
      "min": "-40 C",
      "typ": "25 C",
      "max": "85 C"
    },
    {
      "parameter": "RX Peak Current",
      "min": "-",
      "typ": "4.6 mA",
      "max": "-"
    },
    {
      "parameter": "Sleep Current",
      "min": "-",
      "typ": "100 nA",
      "max": "-"
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/product_specs.json

# 4. Ensure OpenOffice Shortcut exists
if [ -f "/usr/share/applications/openoffice4-writer.desktop" ]; then
    cp "/usr/share/applications/openoffice4-writer.desktop" /home/ga/Desktop/
    chmod +x /home/ga/Desktop/openoffice4-writer.desktop
    chown ga:ga /home/ga/Desktop/openoffice4-writer.desktop
fi

# 5. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists.txt

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Specs created at: /home/ga/Documents/product_specs.json"