#!/bin/bash
set -e
echo "=== Setting up Anchorage Capacity Planning Task ==="

# 1. Define Paths
DOCS_DIR="/home/ga/Documents"
SCENARIOS_DIR="/opt/bridgecommand/Scenarios"
TARGET_SCENARIO="$SCENARIOS_DIR/p) St Helens Storm Anchorage"

# 2. Clean previous state
rm -rf "$TARGET_SCENARIO"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 3. Create 'anchorage_request.txt'
# Defines ships and the safety formula
cat > "$DOCS_DIR/anchorage_request.txt" << EOF
URGENT MEMORANDUM: STORM CIARA ANCHORAGE PLANNING
=================================================
DATE: $(date +%Y-%m-%d)
FROM: Southampton VTS
TO: Duty Planning Officer

We have 6 large vessels requesting immediate anchorage in St Helens Deep Water zone.
Please allocate positions for all vessels below.

VESSEL LIST:
1. Name: Titan
   Type: VLCC
   Length: 330m

2. Name: Global Leader
   Type: Car Carrier
   Length: 200m

3. Name: Ever Given
   Type: Container Ship
   Length: 400m

4. Name: Queen Mary 2
   Type: Passenger
   Length: 345m

5. Name: Gas Monarch
   Type: LPG Tanker
   Length: 230m

6. Name: Atlantic Conveyor
   Type: Ro-Ro
   Length: 290m

SAFETY FORMULA (SWING CIRCLE):
To prevent collisions when the tide turns, use the following calculation for the Safety Radius (R) of each ship:

   R (nm) = (Length (m) * 1.5 / 1852) + 0.15

   * Length is multiplied by 1.5 to account for anchor chain scope.
   * Converted to Nautical Miles (1 NM = 1852m).
   * Plus a fixed Safety Buffer of 0.15 NM.

CONSTRAINT:
The distance between any two ships must be strictly GREATER than the sum of their Safety Radii.
   Distance(A,B) > Radius(A) + Radius(B)

OUTPUT:
Create a Bridge Command scenario "p) St Helens Storm Anchorage" with these ships at valid positions.
EOF
chown ga:ga "$DOCS_DIR/anchorage_request.txt"

# 4. Create 'anchorage_zone.txt'
# Defines the geometric bounds
cat > "$DOCS_DIR/anchorage_zone.txt" << EOF
ST HELENS ANCHORAGE ZONE BOUNDARIES
===================================
All anchors must be dropped strictly within this bounding box:

LATITUDE:
  Minimum: 50.70 N
  Maximum: 50.74 N

LONGITUDE:
  Minimum: -1.09 W
  Maximum: -1.01 W

(Note: Bridge Command uses negative values for West longitude)
EOF
chown ga:ga "$DOCS_DIR/anchorage_zone.txt"

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Ensure Bridge Command isn't running
pkill -f "bridgecommand" || true

echo "=== Setup Complete ==="
echo "Input files created in $DOCS_DIR"