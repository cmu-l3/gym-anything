#!/bin/bash
set -e
echo "=== Setting up Interactive Troubleshooting Guide Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous run artifacts
rm -f /home/ga/Documents/Sentinel_Guide_Interactive.odt 2>/dev/null || true
rm -f /home/ga/Documents/troubleshooting_data.json 2>/dev/null || true

# Create the input JSON data file
cat > /home/ga/Documents/troubleshooting_data.json << 'EOF'
{
  "product": "Sentinel Eye Pro",
  "menu_items": [
    {
      "symptom": "Camera will not turn on / LED off",
      "target_section_title": "Power & Battery",
      "suggested_bookmark_name": "Power"
    },
    {
      "symptom": "Device Offline / Error 502",
      "target_section_title": "Wi-Fi Connectivity",
      "suggested_bookmark_name": "WiFi"
    },
    {
      "symptom": "Image is blurry or washed out at night",
      "target_section_title": "Image Quality & Night Vision",
      "suggested_bookmark_name": "Image"
    },
    {
      "symptom": "No notifications for movement",
      "target_section_title": "Motion Detection Settings",
      "suggested_bookmark_name": "Motion"
    }
  ],
  "sections": [
    {
      "title": "Power & Battery",
      "content": "1. Check the battery level in the Sentinel App. If below 5%, charge for 4 hours.\n2. Inspect the USB-C port for debris.\n3. Hard Reset: Hold the Sync button for 15 seconds until the LED flashes red."
    },
    {
      "title": "Wi-Fi Connectivity",
      "content": "1. Ensure your router is broadcasting a 2.4GHz network (5GHz is not supported).\n2. Move the camera within 10 feet of the router for setup.\n3. Check firewall settings for Port 8883 (MQTT) and Port 443 (HTTPS)."
    },
    {
      "title": "Image Quality & Night Vision",
      "content": "1. IR Reflection: Ensure the camera is not pointed through a window or near a wall that reflects IR light.\n2. Clean the lens with a microfiber cloth.\n3. Adjust 'Night Vision Sensitivity' in the app settings to 'Low' if in a small room."
    },
    {
      "title": "Motion Detection Settings",
      "content": "1. Verify that 'Motion Alerts' are toggled ON in the Notification Center.\n2. Adjust the Activity Zone to exclude busy streets.\n3. Increase Sensitivity if subjects are >20 feet away."
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/troubleshooting_data.json

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# Create OpenOffice Writer desktop shortcut if not exists
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
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
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Input Data: /home/ga/Documents/troubleshooting_data.json"
echo "Expected Output: /home/ga/Documents/Sentinel_Guide_Interactive.odt"