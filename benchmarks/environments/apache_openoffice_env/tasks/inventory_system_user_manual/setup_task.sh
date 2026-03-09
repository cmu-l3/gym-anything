#!/bin/bash
set -e
echo "=== Setting up Inventory System User Manual Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/StockPulse_WMS_User_Manual.odt 2>/dev/null || true
rm -f /home/ga/Documents/system_specs.json 2>/dev/null || true

# 3. Create the System Specs JSON file
# This contains all the raw info the agent needs to write the manual
cat > /home/ga/Documents/system_specs.json << 'EOF'
{
  "document_metadata": {
    "title": "StockPulse WMS End-User Manual",
    "document_number": "CDG-DOC-2024-0047",
    "version": "1.0",
    "date": "2024-11-15",
    "author": "Maya Johansson, Senior Systems Analyst",
    "company": "Cascade Distribution Group, LLC",
    "address": "2800 NW Front Avenue, Portland, OR 97210",
    "classification": "Internal Use Only"
  },
  "system_overview": {
    "name": "StockPulse WMS",
    "version": "3.2.1",
    "description": "Cloud-based warehouse management system for inventory tracking, order fulfillment, and shipping.",
    "facilities": ["Portland (PDX-01)", "Salem (SLE-02)", "Boise (BOI-03)", "Spokane (GEG-04)"]
  },
  "required_sections": [
    "Introduction and System Overview",
    "System Requirements and Login",
    "Dashboard and Navigation",
    "Receiving and Put-Away",
    "Picking, Packing, and Shipping",
    "Cycle Count and Inventory Adjustments",
    "Troubleshooting and Error Codes"
  ],
  "system_requirements": {
    "browser": "Google Chrome 120+ or Microsoft Edge 120+",
    "os": "Windows 10/11 or Android 12+ (for handhelds)",
    "hardware": "Zebra TC52/TC57 Handheld Scanner",
    "network": "Wi-Fi (WPA2-Enterprise) or 100Mbps LAN"
  },
  "keyboard_shortcuts": [
    {"key": "F1", "action": "Open Help Context"},
    {"key": "F2", "action": "Edit Field / Rename"},
    {"key": "F5", "action": "Refresh Data"},
    {"key": "Ctrl+R", "action": "Open Receiving Module"},
    {"key": "Ctrl+P", "action": "Open Picking Module"},
    {"key": "Ctrl+S", "action": "Open Shipping Module"},
    {"key": "Ctrl+L", "action": "Item Lookup"},
    {"key": "Ctrl+F", "action": "Find Order"},
    {"key": "Alt+D", "action": "Return to Dashboard"},
    {"key": "Alt+C", "action": "Cycle Count Entry"},
    {"key": "Alt+R", "action": "Reports Menu"},
    {"key": "Esc", "action": "Cancel Operation / Close Modal"}
  ],
  "workflows": {
    "receiving": [
      "1. Navigate to Inbound > Receive Shipment.",
      "2. Scan the BOL (Bill of Lading) barcode or enter the PO number manually.",
      "3. Verify the carrier and trailer number.",
      "4. Click 'Start Unload'.",
      "5. For each pallet, scan the SSCC license plate.",
      "6. Verify item quantities against the ASN (Advanced Ship Notice).",
      "7. If damaged, mark status as 'Quarantine' and take a photo.",
      "8. Click 'Finalize Receipt' when all pallets are scanned."
    ],
    "picking": [
      "1. Navigate to Outbound > Wave Pick.",
      "2. Select the assigned Wave ID.",
      "3. Travel to the location displayed on the scanner.",
      "4. Scan the location barcode to confirm arrival.",
      "5. Scan the item UPC.",
      "6. Enter the quantity picked.",
      "7. Place item in the tote and scan the tote LPN."
    ],
    "cycle_count": [
      "1. Navigate to Inventory > Cycle Count.",
      "2. Scan the location label.",
      "3. Blind count: Enter the total quantity found physically.",
      "4. System compares with recorded Qty. If match, count is approved.",
      "5. If mismatch, system prompts for a recount.",
      "6. If second count mismatches, a Supervisor Approval task is generated."
    ]
  },
  "error_codes": [
    {"code": "ERR-1001", "description": "Invalid Barcode Format", "resolution": "Check label for damage. Ensure scanner lens is clean."},
    {"code": "ERR-1002", "description": "Location Locked", "resolution": "Location is currently being counted. Wait 5 minutes or contact supervisor."},
    {"code": "ERR-1005", "description": "SKU Not Found", "resolution": "Verify item exists in Item Master. Check for discontinued status."},
    {"code": "ERR-2001", "description": "User Not Authorized", "resolution": "Contact IT Admin to adjust permission groups."},
    {"code": "ERR-3000", "description": "API Timeout", "resolution": "Check Wi-Fi signal. Re-try operation."},
    {"code": "ERR-4004", "description": "Order Cancelled", "resolution": "Order was cancelled by ERP. Return items to stock."},
    {"code": "ERR-5000", "description": "Printer Offline", "resolution": "Check paper/ribbon. Restart printer."}
  ],
  "glossary": {
    "ASN": "Advanced Ship Notice - Electronic notification of pending deliveries.",
    "BOL": "Bill of Lading - Legal document issuing carrier details.",
    "LPN": "License Plate Number - Unique ID for a pallet or carton.",
    "SKU": "Stock Keeping Unit - Unique identifier for a distinct product.",
    "WMS": "Warehouse Management System.",
    "Zone": "A specific area of the warehouse (e.g., Cold Storage, Bulk)."
  }
}
EOF
chown ga:ga /home/ga/Documents/system_specs.json

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenOffice Writer (blank document)
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
fi

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
        echo "Writer window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="