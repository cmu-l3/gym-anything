#!/bin/bash
echo "=== Setting up deck_log_reconstruction task ==="

# Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/deck_log.txt
rm -f /home/ga/Documents/voyage_statistics.txt

# Ensure Scenarios directory exists and is readable
if [ ! -d "/opt/bridgecommand/Scenarios" ]; then
    echo "ERROR: Scenarios directory not found!"
    exit 1
fi

# Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Create a small sample scenario to ensure there is at least one known waypoint case
# This ensures the agent has to implement the Haversine logic
SAMPLE_SCENARIO="/opt/bridgecommand/Scenarios/z_Test_Waypoint_Nav"
if [ ! -d "$SAMPLE_SCENARIO" ]; then
    echo "Creating test scenario with waypoints..."
    mkdir -p "$SAMPLE_SCENARIO"
    
    # Environment
    cat > "$SAMPLE_SCENARIO/environment.ini" << EOF
Setting="Open Sea"
StartTime=12.0
StartDay=15
StartMonth=6
StartYear=2023
Weather=3
VisibilityRange=15.0
RainIntensity=0
SunRise=6.0
SunSet=20.0
EOF

    # Ownship (Start -> Leg1 -> Leg2)
    # Start: 50.0N, 0.0E
    # Leg1: 50.0N, 1.0E (~38.6 nm)
    # Leg2: 51.0N, 1.0E (~60 nm)
    cat > "$SAMPLE_SCENARIO/ownship.ini" << EOF
ShipName="Test Vessel"
InitialLat=50.0
InitialLong=0.0
InitialBearing=90
InitialSpeed=10.0
Leg(1)Lat=50.0
Leg(1)Long=1.0
Leg(1)Speed=10.0
Leg(2)Lat=51.0
Leg(2)Long=1.0
Leg(2)Speed=10.0
EOF

    # Othership
    cat > "$SAMPLE_SCENARIO/othership.ini" << EOF
Number=1
Type(1)="Coaster"
InitialLat(1)=50.5
InitialLong(1)=0.5
InitialBearing(1)=270
InitialSpeed(1)=8.0
EOF
    
    chown -R root:root "$SAMPLE_SCENARIO"
    chmod -R 755 "$SAMPLE_SCENARIO"
fi

# Capture initial state for debugging
echo "Scenario count: $(ls -d /opt/bridgecommand/Scenarios/*/ | wc -l)"

# Setup complete
echo "=== Task setup complete ==="
echo "Files to generate:"
echo "  1. /home/ga/Documents/deck_log.txt"
echo "  2. /home/ga/Documents/voyage_statistics.txt"
echo "Source Data: /opt/bridgecommand/Scenarios/"