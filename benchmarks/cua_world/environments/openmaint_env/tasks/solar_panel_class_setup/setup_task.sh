#!/bin/bash
set -e
echo "=== Setting up solar_panel_class_setup ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# 1. Create the specification file on the desktop
cat > /home/ga/Desktop/solar_panel_spec.txt << 'EOF'
SOLAR PANEL TRACKING - OPENMAINT CONFIGURATION REQUEST
=======================================================

1. CLASS SETUP
   - Create a new class named: SolarPanel
   - It should be a subclass of a CI-type superclass (such as CI, Equipment,
     InternalItem, or another available CI superclass in the hierarchy)
   - The class must be set to Active

2. CUSTOM ATTRIBUTES (add to SolarPanel class)
   a) PanelCapacityKW  - Type: Decimal   - Total panel capacity in kilowatts
   b) InstallationDate - Type: Date      - Date of panel installation
   c) Manufacturer     - Type: String    - Solar panel manufacturer name
   d) InverterType     - Type: String    - Inverter make and model
   e) PanelCount       - Type: Integer   - Number of individual panels

3. INITIAL RECORDS (create after class is configured)

   Record 1:
     Code: SP-BLD1-001
     Building: (first building in system)
     PanelCapacityKW: 150.0
     InstallationDate: 2025-01-15
     Manufacturer: SunPower
     InverterType: SMA Sunny Tripower 15000TL
     PanelCount: 42

   Record 2:
     Code: SP-BLD2-001
     Building: (second building in system)
     PanelCapacityKW: 200.0
     InstallationDate: 2025-02-20
     Manufacturer: Canadian Solar
     InverterType: Fronius Symo 20.0-3-M
     PanelCount: 56

   Record 3:
     Code: SP-BLD3-001
     Building: (third building in system)
     PanelCapacityKW: 75.5
     InstallationDate: 2025-03-10
     Manufacturer: LONGi Green Energy
     InverterType: Huawei SUN2000-8KTL-M1
     PanelCount: 22

NOTES:
- Assign each record to a different building from the existing building list
- Ensure all attributes are saved before creating records
- Do NOT modify or delete any existing classes or data
EOF

chown ga:ga /home/ga/Desktop/solar_panel_spec.txt

# 2. Record baseline state (Python)
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(1)

# List existing classes to ensure we detect new ones later
classes = list_classes(token)
class_names = [c.get("_id") for c in classes]

# Get buildings to verify linkage later
buildings = get_buildings(token)
bld_info = []
for b in buildings[:5]:
    bld_info.append({
        "id": b.get("_id"),
        "code": b.get("Code", ""),
        "desc": b.get("Description", "")
    })

baseline = {
    "initial_class_count": len(classes),
    "initial_class_names": class_names,
    "buildings": bld_info
}

save_baseline("/tmp/sp_baseline.json", baseline)
print("Baseline saved to /tmp/sp_baseline.json")
PYEOF

# 3. Timestamp start
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_sp.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Force navigation
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/task_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== Task setup complete ==="