#!/bin/bash
# setup_task.sh — Maritime Infrastructure Taxonomy Customization
# Writes the taxonomy specification and generates icon files.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Generate maritime taxonomy spec and icon files
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop/maritime_taxonomy"
ICONS_DIR="$DESKTOP_DIR/icons"

mkdir -p "$ICONS_DIR"

# Generate simple PNG icons using ImageMagick (fallback to base64 embedded tiny PNGs)
convert -size 64x64 xc:blue "$ICONS_DIR/vsat_terminal.png" 2>/dev/null || \
    base64 -d <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" > "$ICONS_DIR/vsat_terminal.png"

convert -size 64x64 xc:green "$ICONS_DIR/iot_gateway.png" 2>/dev/null || \
    base64 -d <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" > "$ICONS_DIR/iot_gateway.png"

convert -size 64x64 xc:red "$ICONS_DIR/marine_radar.png" 2>/dev/null || \
    base64 -d <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" > "$ICONS_DIR/marine_radar.png"

cat > "$DESKTOP_DIR/taxonomy_spec.txt" << 'SPEC_EOF'
MARITIME INFRASTRUCTURE TAXONOMY SPECIFICATION
===============================================
Please add the following device categories to OpManager to support our maritime fleet monitoring.
Navigate to Settings > Configuration > Device Categories.

Category 1:
- Category Name: VSAT-Terminal
- Parent Category: Network
- Icon File: vsat_terminal.png

Category 2:
- Category Name: Vessel-IoT-Gateway
- Parent Category: Router
- Icon File: iot_gateway.png

Category 3:
- Category Name: Navigational-Radar
- Parent Category: Server
- Icon File: marine_radar.png

Make sure to upload the corresponding PNG files located in the 'icons' folder on the desktop.
SPEC_EOF

chown -R ga:ga "$DESKTOP_DIR"
echo "[setup] Taxonomy files prepared in $DESKTOP_DIR"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/maritime_taxonomy_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/maritime_taxonomy_setup_screenshot.png" || true

echo "[setup] maritime_infrastructure_taxonomy_customization setup complete."