#!/bin/bash
echo "=== Setting up Hydrographic Survey Planning Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents"
SPECS_FILE="$DOCS_DIR/Survey_Mission_Specs.txt"
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/Hydrographic_Survey"

# Create Documents directory
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Clean up previous run
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$SPECS_FILE" 2>/dev/null || true

# Detect available worlds to ensure valid coordinates
# Default to Solent if available, else SantaCatalina
WORLD_SETTING="SantaCatalina"
DATUM_LAT="33.4000"
DATUM_LONG="-118.4000"
ORIENTATION="090"
SPACING="0.2" # nm
LENGTH="1.0"  # nm

if [ -d "$BC_DATA/World/Solent" ]; then
    WORLD_SETTING="Solent"
    DATUM_LAT="50.7800"
    DATUM_LONG="-1.1200"
    ORIENTATION="090" # East-West lines
    SPACING="0.15"    # nm
    LENGTH="1.5"      # nm
fi

# Generate the Mission Specs file
cat > "$SPECS_FILE" << EOF
HYDROGRAPHIC SURVEY MISSION ORDER #2024-SURV-05
===============================================

OBJECTIVE:
Create a simulation scenario to pre-validate track lines for a bathymetric survey.

ENVIRONMENT:
- World Setting: ${WORLD_SETTING}
- Conditions: Daytime, Good Visibility, Calm Sea

VESSEL CONFIGURATION:
- Name: Survey_Vessel_1
- Speed: 8.0 knots

SURVEY PATTERN PARAMETERS:
- Pattern Type: Parallel Track (Lawnmower)
- Start Point (Datum): Lat ${DATUM_LAT}, Long ${DATUM_LONG}
- Initial Heading: ${ORIENTATION} degrees (True)
- Line Length: ${LENGTH} nautical miles
- Line Spacing: ${SPACING} nautical miles
- Cross-track Direction: South (Turn Right/Starboard at end of first line)
- Total Survey Lines: 6

INSTRUCTIONS:
Calculate the necessary waypoints to achieve this pattern and create the Bridge Command scenario files.
The scenario must be saved in: /opt/bridgecommand/Scenarios/Hydrographic_Survey/
EOF

chown ga:ga "$SPECS_FILE"

# Save truth data for verification
cat > /tmp/survey_truth.json << EOF
{
    "world": "${WORLD_SETTING}",
    "datum_lat": ${DATUM_LAT},
    "datum_long": ${DATUM_LONG},
    "orientation": ${ORIENTATION},
    "spacing": ${SPACING},
    "length": ${LENGTH},
    "lines": 6,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Bridge Command is ready (not running, but installed)
pkill -f "bridgecommand" 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Mission specs generated at $SPECS_FILE"