#!/bin/bash
set -e
echo "=== Setting up inbound_asset_receiving ==="

source /workspace/scripts/task_utils.sh

# Ensure OpenMaint is running
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Generate the packing slip
cat > /home/ga/Desktop/packing_slip_INV-9920.txt << 'EOF'
==============================================================================
PACKING SLIP / INBOUND MANIFEST
Order: INV-9920
Date: 2026-03-08
Vendor: Dell Technologies
Ship To: IT Receiving Dock
==============================================================================

SECTION 1: CURRENT SHIPMENT
------------------------------------------------------------------------------
#  | Item Description             | Serial Number           | Condition
------------------------------------------------------------------------------
01 | Dell Latitude 5520 Laptop    | 8H29F2X                 | OK
02 | Dell Latitude 5520 Laptop    | 9J30G3Y                 | DAMAGED / SCREEN CRACKED
03 | Dell P2419H 24" Monitor      | CN-0Y9N-71618-88A-123   | OK
04 | Dell P2419H 24" Monitor      | CN-0Y9N-71618-88A-124   | OK

SECTION 2: BACKORDER FULFILLED (PREVIOUSLY SHIPPED)
------------------------------------------------------------------------------
NOTE: These items were shipped in a previous box. Do NOT re-process.
------------------------------------------------------------------------------
#  | Item Description             | Serial Number           | Status
------------------------------------------------------------------------------
05 | Dell WD19 USB-C Docking Stn  | BC-1122-3344            | Delivered 2026-03-01
==============================================================================
EOF

chown ga:ga /home/ga/Desktop/packing_slip_INV-9920.txt

# Record initial state (clean up any pre-existing records with these serials just in case)
python3 << 'PYEOF'
import sys, json
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Authentication failed", file=sys.stderr)
    sys.exit(1)

# List of serials involved in this task
target_serials = [
    "8H29F2X",                # Valid Laptop
    "9J30G3Y",                # Damaged Laptop
    "CN-0Y9N-71618-88A-123",  # Valid Monitor 1
    "CN-0Y9N-71618-88A-124",  # Valid Monitor 2
    "BC-1122-3344"            # Backorder Dock
]

# Try to find relevant classes to clean up
candidate_classes = ["Computer", "Equipment", "Asset", "CI", "Peripheral"]
classes_found = []
for c in candidate_classes:
    if find_class(c, token):
        classes_found.append(find_class(c, token))

print(f"Cleaning up target serials in classes: {classes_found}")

# Cleanup logic: Find and delete any existing cards with these serials
# This ensures the agent starts with a clean slate for these specific items
for cls in classes_found:
    cards = get_cards(cls, token, limit=1000)
    for card in cards:
        # Check standard fields for serial number
        serial = card.get("SerialNumber") or card.get("Serial") or card.get("SN") or ""
        if serial in target_serials:
            print(f"Deleting pre-existing card {card.get('_id')} with serial {serial}")
            delete_card(cls, card.get("_id"), token)

# Save baseline info
baseline = {
    "task_start_time": int(time.time()),
    "classes_available": classes_found
}
save_baseline("/tmp/iar_baseline.json", baseline)
PYEOF

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_setup.log 2>&1 &"

if wait_for_window "firefox|mozilla|openmaint" 40; then
    focus_firefox || true
    su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type '$OPENMAINT_URL'"
    su - ga -c "DISPLAY=:1 xdotool key Return"
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="