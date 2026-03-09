#!/bin/bash
# set -euo pipefail

echo "=== Setting up QGIS configuration ==="

# Set up QGIS for a specific user
setup_user_qgis() {
    local username=$1
    local home_dir=$2

    echo "Setting up QGIS for user: $username"

    # Give recursive full permissions to the user cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create QGIS config directories (QGIS 3.x uses .local/share/QGIS)
    sudo -u $username mkdir -p "$home_dir/.local/share/QGIS/QGIS3/profiles/default"
    sudo -u $username mkdir -p "$home_dir/.config/QGIS"
    sudo -u $username mkdir -p "$home_dir/.cache/QGIS"

    # Create GIS data directories
    sudo -u $username mkdir -p "$home_dir/GIS_Data"
    sudo -u $username mkdir -p "$home_dir/GIS_Data/shapefiles"
    sudo -u $username mkdir -p "$home_dir/GIS_Data/rasters"
    sudo -u $username mkdir -p "$home_dir/GIS_Data/projects"
    sudo -u $username mkdir -p "$home_dir/GIS_Data/exports"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create QGIS3.ini to disable first-run dialogs and tips
    cat > "$home_dir/.config/QGIS/QGIS3.ini" << 'QGISINIEOF'
[General]
locale/userLocale=en_US
showTips=false

[UI]
tips/sketcher/sketcher_sketcher=false

[qgis]
showTips=false
askToSaveProjectChanges=false
WelcomePageDisabled=true
checkForUpdateNotice=false
promptForProjectChanges=false

[news]
sketcher/sketcher_sketcher=sketcher_sketcher
sketcher/sketcher_sketcher_sketcher=sketcher_sketcher_sketcher
sketcher/sketcher_sketcher_sketcher_sketcher=sketcher_sketcher_sketcher_sketcher

[projections]
defaultBehavior=useProject

[Processing]
Configuration/ACTIVATE_SKETCHER=sketcher_sketcher_sketcher
QGISINIEOF
    chown $username:$username "$home_dir/.config/QGIS/QGIS3.ini"
    echo "  - Created QGIS3.ini configuration"

    # Generate sample GeoJSON data (simple polygon)
    echo "  - Generating sample GeoJSON data..."
    cat > "$home_dir/GIS_Data/sample_polygon.geojson" << 'GEOJSONEOF'
{
  "type": "FeatureCollection",
  "name": "sample_polygon",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    {
      "type": "Feature",
      "properties": { "id": 1, "name": "Area A", "area_sqkm": 10.5 },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.5, 37.5], [-122.5, 37.8], [-122.2, 37.8], [-122.2, 37.5], [-122.5, 37.5]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 2, "name": "Area B", "area_sqkm": 8.2 },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.2, 37.5], [-122.2, 37.8], [-121.9, 37.8], [-121.9, 37.5], [-122.2, 37.5]]]
      }
    }
  ]
}
GEOJSONEOF
    chown $username:$username "$home_dir/GIS_Data/sample_polygon.geojson"

    # Generate sample point data
    cat > "$home_dir/GIS_Data/sample_points.geojson" << 'POINTSEOF'
{
  "type": "FeatureCollection",
  "name": "sample_points",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Point A", "elevation": 100 }, "geometry": { "type": "Point", "coordinates": [-122.4, 37.6] } },
    { "type": "Feature", "properties": { "id": 2, "name": "Point B", "elevation": 150 }, "geometry": { "type": "Point", "coordinates": [-122.3, 37.7] } },
    { "type": "Feature", "properties": { "id": 3, "name": "Point C", "elevation": 200 }, "geometry": { "type": "Point", "coordinates": [-122.1, 37.65] } }
  ]
}
POINTSEOF
    chown $username:$username "$home_dir/GIS_Data/sample_points.geojson"

    # Generate sample line data (roads/paths)
    cat > "$home_dir/GIS_Data/sample_lines.geojson" << 'LINESEOF'
{
  "type": "FeatureCollection",
  "name": "sample_lines",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "id": 1, "name": "Road 1", "type": "highway" }, "geometry": { "type": "LineString", "coordinates": [[-122.5, 37.5], [-122.3, 37.6], [-122.1, 37.7]] } },
    { "type": "Feature", "properties": { "id": 2, "name": "Road 2", "type": "secondary" }, "geometry": { "type": "LineString", "coordinates": [[-122.4, 37.5], [-122.4, 37.8]] } }
  ]
}
LINESEOF
    chown $username:$username "$home_dir/GIS_Data/sample_lines.geojson"

    # Set proper permissions for all GIS data
    chown -R $username:$username "$home_dir/GIS_Data"
    chown -R $username:$username "$home_dir/.local/share/QGIS" 2>/dev/null || true
    chown -R $username:$username "$home_dir/.config/QGIS" 2>/dev/null || true

    # Create desktop shortcut
    cat > "$home_dir/Desktop/QGIS.desktop" << DESKTOPEOF
[Desktop Entry]
Name=QGIS Desktop
Comment=Geographic Information System
Exec=qgis %F
Icon=qgis
StartupNotify=true
Terminal=false
MimeType=application/x-qgis-project;application/x-qgis-layer-definition;
Categories=Education;Science;Geography;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/QGIS.desktop"
    chmod +x "$home_dir/Desktop/QGIS.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_qgis.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch QGIS with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Disable QGIS tips and welcome dialog
export QGIS_SKETCHER=sketcher_sketcher_sketcher

# Launch QGIS
qgis "$@" > /tmp/qgis_$USER.log 2>&1 &

echo "QGIS started"
echo "Log file: /tmp/qgis_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_qgis.sh"
    chmod +x "$home_dir/launch_qgis.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_qgis "ga" "/home/ga"
fi

# Create utility scripts
cat > /usr/local/bin/qgis-info << 'INFOEOF'
#!/bin/bash
# QGIS info utility
# Usage: qgis-info [project_file]

echo "=== QGIS Information ==="
echo ""

if [ $# -eq 0 ]; then
    echo "QGIS version:"
    qgis --version 2>&1 | head -5
    echo ""
    echo "Available QGIS profiles:"
    ls -la ~/.local/share/QGIS/QGIS3/profiles/ 2>/dev/null || echo "No profiles found"
else
    echo "Project file: $1"
    if [ -f "$1" ]; then
        echo "File size: $(stat -c%s "$1" 2>/dev/null || echo 'unknown') bytes"
        echo "File type: $(file "$1" 2>/dev/null || echo 'unknown')"
        # For QGS files, show basic XML info
        if [[ "$1" == *.qgs ]]; then
            echo ""
            echo "Project layers (from XML):"
            grep -o 'name="[^"]*"' "$1" 2>/dev/null | head -10 || echo "Could not parse layers"
        fi
    else
        echo "File not found: $1"
    fi
fi
INFOEOF
chmod +x /usr/local/bin/qgis-info

echo "=== QGIS configuration completed ==="

# Do not auto-launch QGIS here - let task scripts handle launching
echo "QGIS is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'qgis' from terminal"
echo "  - Run '~/launch_qgis.sh [project]' for optimized launch"
echo "  - Use 'qgis-info [project]' to inspect project files"
echo ""
echo "Sample data available in ~/GIS_Data/"
