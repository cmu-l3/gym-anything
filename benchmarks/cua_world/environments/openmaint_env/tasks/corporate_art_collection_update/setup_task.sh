#!/bin/bash
set -e
echo "=== Setting up corporate_art_collection_update ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the manifest file
cat > /home/ga/Desktop/art_manifest.txt << 'EOF'
=== METROPOLIS TOWER ART ACQUISITIONS ===
Date: 2026-05-15
Curator: A. Vance

POLICY NOTICE:
Register individual assets ONLY for items with insurance value > $1,000.
Items under $1,000 are tracked in the bulk ledger, NOT in OpenMaint.

ITEMS:

1. Code: ART-NEW-001
   Item: "Blue Horizon" (Oil on Canvas)
   Artist: Sarah Jenkins
   Location: Main Lobby
   Value: $15,000

2. Code: ART-NEW-002
   Item: "Steel Vector" (Sculpture)
   Artist: Marcus Thorne
   Location: Exterior Plaza
   Value: $22,500

3. Code: ART-NEW-003
   Item: "Lobby Print #405" (Lithograph)
   Artist: Unknown
   Location: Elevator Bank B
   Value: $450

INSTRUCTIONS:
- Create assets in OpenMaint for qualifying items.
- Also, please flag existing asset ART-OLD-004 (Vintage Tapestry) as DAMAGED.
  Housekeeping reported a leak above it.
EOF
chmod 644 /home/ga/Desktop/art_manifest.txt
chown ga:ga /home/ga/Desktop/art_manifest.txt

# Setup database state using Python script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find appropriate class for Assets
# We look for "Furniture", "Decor", or generic "Asset"
asset_cls = None
for pattern in ["Furniture", "Decor", "Asset", "CI", "Equipment"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break

if not asset_cls:
    # Fallback: List all classes and pick the first reasonable one
    print("WARNING: Could not find specific asset class, searching broader list...")
    all_classes = list_classes(token)
    for c in all_classes:
        if not c.get("superclass"): # approximations
            asset_cls = c.get("_id")
            break

print(f"Selected Asset Class: {asset_cls}")

# 2. Create Building "Metropolis Tower"
building_data = {
    "Code": "BLD-METRO",
    "Description": "Metropolis Tower"
}
# Check if exists first
existing_bld = get_cards("Building", token, filter_str="filter={\"attribute\":{\"simple\":{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"BLD-METRO\"]}}}")
if existing_bld:
    bld_id = existing_bld[0]["_id"]
    print(f"Building BLD-METRO already exists: {bld_id}")
else:
    bld_id = create_card("Building", building_data, token)
    print(f"Created Building BLD-METRO: {bld_id}")

# 3. Create existing asset "ART-OLD-004"
# We need to find valid attributes for the asset class
attrs = get_class_attributes(asset_cls, token)
attr_names = [a.get("_id") for a in attrs]

art_data = {
    "Code": "ART-OLD-004",
    "Description": "Vintage Tapestry - 19th Century",
    "Notes": "Condition: Good"
}

# Add building reference if field exists
# Common names for building reference: Building, Location, Site
bld_field = None
for f in ["Building", "Location", "Site"]:
    if f in attr_names:
        bld_field = f
        break

if bld_field and bld_id:
    art_data[bld_field] = bld_id

# Create the asset
existing_art = get_cards(asset_cls, token, filter_str="filter={\"attribute\":{\"simple\":{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"ART-OLD-004\"]}}}")
if existing_art:
    art_id = existing_art[0]["_id"]
    # Reset state if it exists
    update_card(asset_cls, art_id, art_data, token)
    print(f"Reset existing asset ART-OLD-004: {art_id}")
else:
    art_id = create_card(asset_cls, art_data, token)
    print(f"Created existing asset ART-OLD-004: {art_id}")

# Save setup info for verification
setup_info = {
    "asset_class": asset_cls,
    "building_id": bld_id,
    "art_old_id": art_id,
    "building_field": bld_field
}
with open("/tmp/art_task_setup.json", "w") as f:
    json.dump(setup_info, f)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Start Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 60; then
  echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="