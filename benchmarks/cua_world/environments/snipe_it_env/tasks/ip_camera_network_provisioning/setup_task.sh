#!/bin/bash
echo "=== Setting up ip_camera_network_provisioning task ==="

source /workspace/scripts/task_utils.sh

# Helper to extract ID
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

echo "  Creating Location..."
LOC_CHICAGO=$(get_id "$(snipeit_api POST "locations" '{"name":"Chicago Facility","city":"Chicago"}')")
echo "  Location ID: $LOC_CHICAGO"

echo "  Creating Category & Manufacturer..."
CAT_CAM=$(get_id "$(snipeit_api POST "categories" '{"name":"Security Cameras","category_type":"asset"}')")
MFG_MERAKI=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Meraki"}')")

echo "  Creating Custom Fieldset and Fields..."
FIELDSET_ID=$(get_id "$(snipeit_api POST "fieldsets" '{"name":"Network Details"}')")
IP_FIELD_ID=$(get_id "$(snipeit_api POST "fields" '{"name":"IP Address","element":"text","format":"IP"}')")
MAC_FIELD_ID=$(get_id "$(snipeit_api POST "fields" '{"name":"MAC Address","element":"text","format":"MAC"}')")

# Attach fields to fieldset
if [ -n "$FIELDSET_ID" ] && [ -n "$IP_FIELD_ID" ]; then
    snipeit_api POST "fieldsets/${FIELDSET_ID}/fields" "{\"field_id\":${IP_FIELD_ID},\"required\":false,\"order\":1}"
fi
if [ -n "$FIELDSET_ID" ] && [ -n "$MAC_FIELD_ID" ]; then
    snipeit_api POST "fieldsets/${FIELDSET_ID}/fields" "{\"field_id\":${MAC_FIELD_ID},\"required\":false,\"order\":2}"
fi

echo "  Creating Asset Model..."
MODEL_MV22=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Meraki MV22\",\"category_id\":${CAT_CAM:-1},\"manufacturer_id\":${MFG_MERAKI:-1},\"fieldset_id\":${FIELDSET_ID:-null}}")")

echo "  Creating Status Label..."
STATUS_DEFECTIVE=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Defective","type":"undeployable"}')")

STATUS_READY=$(snipeit_api GET "statuslabels" "" | jq -r '.rows[] | select(.name=="Ready to Deploy") | .id' | head -1)

echo "  Creating 6 camera assets..."
for i in {1..6}; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"CAM-010$i\",\"name\":\"Meraki MV22 Camera 010$i\",\"model_id\":${MODEL_MV22},\"status_id\":${STATUS_READY}}"
done

echo "  Creating Deployment Manifest..."
cat > /home/ga/Desktop/camera_network_config.txt << 'EOF'
Date: March 9, 2026
To: IT Asset Management Team
From: Network Operations
Subject: Chicago Facility (Building 2) Camera Deployment Manifest

Please provision the following Meraki MV22 cameras in Snipe-IT before the installers arrive tomorrow. Assign them to the Chicago Facility location and embed the networking details.

Tag        MAC Address          IP Address      Deployment Notes
-------------------------------------------------------------------------
CAM-0101   E0:CB:4E:AA:BB:01    10.40.50.101    Main Entrance Overhang
CAM-0102   E0:CB:4E:AA:BB:02    10.40.50.102    Loading Dock A (North)
CAM-0103   E0:CB:4E:AA:BB:03    10.40.50.103    Loading Dock B (South)
CAM-0104   E0:CB:4E:AA:BB:04    10.40.50.104    Breakroom Hallway
CAM-0105   E0:CB:4E:AA:BB:05    10.40.50.105    Server Room MDF

* Note: CAM-0106 (E0:CB:4E:AA:BB:06) was found with a cracked lens during unboxing. Do not deploy or assign an IP. Mark it as Defective so RMA process can begin. Notes: DOA - Lens cracked. Do not deploy.
EOF
chown ga:ga /home/ga/Desktop/camera_network_config.txt

echo "  Recording initial states..."
echo "$LOC_CHICAGO" > /tmp/loc_chicago_id.txt
echo "$STATUS_DEFECTIVE" > /tmp/status_defective_id.txt
get_asset_count > /tmp/initial_asset_count.txt
date +%s > /tmp/task_start_time.txt

echo "  Starting Firefox..."
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="