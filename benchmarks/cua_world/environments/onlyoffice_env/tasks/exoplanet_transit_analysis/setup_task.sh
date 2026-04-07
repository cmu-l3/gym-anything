#!/bin/bash
set -euo pipefail

echo "=== Setting up Exoplanet Transit Analysis Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Load ONLYOFFICE utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    kill_onlyoffice ga 2>/dev/null || true
    cleanup_temp_files 2>/dev/null || true
fi

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# ============================================================================
# Create the Kepler-8 System Parameters File
# ============================================================================
cat > "$DOCS_DIR/system_parameters.txt" << 'EOF'
KEPLER-8 SYSTEM PARAMETERS
--------------------------
Host Star Radius (R_star): 1.48 Solar Radii
Orbital Period: 3.5225 days
Transit Epoch (T0): 134.0 (KBJD - Kepler Barycentric Julian Date)
Conversion Factor: 1 Solar Radius = 9.73 Jupiter Radii (R_J)
EOF

chown ga:ga "$DOCS_DIR/system_parameters.txt"

# ============================================================================
# Generate Realistic Kepler-8b Light Curve Data
# ============================================================================
cat > /tmp/generate_lightcurve.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import math
import sys

output_path = sys.argv[1]
random.seed(42)  # Deterministic seed for verification

# Kepler-8b properties
epoch = 134.0
period = 3.5225
transit_depth = 0.0105
base_flux = 150000.0
transit_duration_phase = 0.035  # fraction of orbit

# Generate 30 days of data at ~30 min cadence (~1440 points)
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["TIME", "SAP_FLUX"])
    
    for i in range(1440):
        t = 130.0 + i * (30.0 / 1440.0)
        
        # Calculate phase
        phase = ((t - epoch) % period) / period
        if phase > 0.5:
            phase -= 1.0
            
        # Add realistic Gaussian noise (photon noise + instrumental)
        flux = base_flux + random.gauss(0, 300)
        
        # Inject transit signal (simple U-shape model)
        if abs(phase) < transit_duration_phase / 2:
            # Add some limb darkening curvature approximation
            impact = abs(phase) / (transit_duration_phase / 2)
            limb_factor = 1.0 - 0.2 * (impact ** 2)
            flux -= base_flux * transit_depth * limb_factor
            
        writer.writerow([round(t, 6), round(flux, 2)])

print(f"Generated light curve at {output_path}")
PYEOF

chmod +x /tmp/generate_lightcurve.py
sudo -u ga /tmp/generate_lightcurve.py "$WORKSPACE_DIR/kepler8b_lightcurve.csv"

# ============================================================================
# Launch Application
# ============================================================================
echo "Starting ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell '$WORKSPACE_DIR/kepler8b_lightcurve.csv' > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE\|Desktop Editors"; then
        echo "ONLYOFFICE window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'ONLYOFFICE\|Desktop Editors' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="