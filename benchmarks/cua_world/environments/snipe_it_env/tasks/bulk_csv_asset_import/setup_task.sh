#!/bin/bash
echo "=== Setting up bulk_csv_asset_import task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial asset count
INITIAL_COUNT=$(get_asset_count)
echo "$INITIAL_COUNT" > /tmp/initial_asset_count.txt

# Remove any pre-existing ENG-LAB assets
for i in $(seq -w 1 10); do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='ENG-LAB-0${i}'" 2>/dev/null || true
done

# Verify location exists, if not, create it
LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='HQ - Floor 2' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_ID" ]; then
    echo "Creating location 'HQ - Floor 2'..."
    snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('HQ - Floor 2', NOW(), NOW())"
fi

# Create CSV file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/import_manifest.csv << 'CSVEOF'
Asset Tag,Asset Name,Serial Number,Model Name,Category,Status,Location,Purchase Date,Purchase Cost,Order Number,Notes
ENG-LAB-001,Engineering Lab PC 1,SN-DL7090-4521,Dell OptiPlex 7090,Desktops,Ready to Deploy,HQ - Floor 2,2024-08-15,1249.99,PO-2024-0892,New lab workstation
ENG-LAB-002,Engineering Lab PC 2,SN-DL7090-4522,Dell OptiPlex 7090,Desktops,Ready to Deploy,HQ - Floor 2,2024-08-15,1249.99,PO-2024-0892,New lab workstation
ENG-LAB-003,Engineering Lab PC 3,SN-DL7090-4253,Dell OptiPlex 7090,Desktops,Ready to Deploy,HQ - Floor 2,2024-08-15,1249.99,PO-2024-0892,New lab workstation
ENG-LAB-004,Engineering Lab Monitor 1,SN-DLU27-8801,Dell UltraSharp U2722D,Monitors,Ready to Deploy,HQ - Floor 2,2024-08-15,589.99,PO-2024-0892,New lab monitor
ENG-LAB-005,Engineering Lab Monitor 2,SN-DLU27-8802,Dell UltraSharp U2722D,Monitors,Ready to Deploy,HQ - Floor 2,2024-08-15,589.99,PO-2024-0892,New lab monitor
ENG-LAB-006,Engineering Lab Monitor 3,SN-DLU27-8803,Dell UltraSharp U2722D,Monitors,Ready to Deploy,HQ - Floor 2,2024-08-15,589.99,PO-2024-0892,New lab monitor
ENG-LAB-007,Engineering Lab Laptop 1,SN-DL5530-9901,Dell Latitude 5530,Laptops,Ready to Deploy,HQ - Floor 2,2024-08-20,1429.00,PO-2024-0893,Portable lab workstation
ENG-LAB-008,Engineering Lab Laptop 2,SN-DL5530-WXYZ,Dell Latitude 5530,Laptops,Ready to Deploy,HQ - Floor 2,2024-08-20,1429.00,PO-2024-0893,Portable lab workstation
ENG-LAB-009,Engineering Lab Switch,SN-CISCO-C9200-5501,Cisco Catalyst 9200,Networking,Ready to Deploy,HQ - Floor 2,2024-08-10,3850.00,PO-2024-0891,Lab network switch
ENG-LAB-010,Engineering Lab AP,SN-UBNT-UAP-7701,Ubiquiti UniFi AP Pro,Networking,Ready to Deploy,HQ - Floor 2,2024-08-10,299.00,PO-2024-0891,Lab wireless access point
CSVEOF

chown ga:ga /home/ga/Documents/import_manifest.csv
chmod 644 /home/ga/Documents/import_manifest.csv

# Ensure Firefox is on Snipe-IT
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 3
focus_firefox

# Click on center to select desktop, then refocus (standard gui setup pattern)
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5
focus_firefox

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="