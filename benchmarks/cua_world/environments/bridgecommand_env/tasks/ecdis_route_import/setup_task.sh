#!/bin/bash
echo "=== Setting up ECDIS Route Import Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents"
RTZ_FILE="$DOCS_DIR/voyage_plan.rtz"
TARGET_SCENARIO="/opt/bridgecommand/Scenarios/Imported ECDIS Route"

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Clean up previous run artifacts
if [ -d "$TARGET_SCENARIO" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$TARGET_SCENARIO"
fi

# Generate the RTZ (XML) file with realistic data
# Waypoints:
# 1. Start: 50.6920 N, 1.0000 W (South of Portsmouth)
# 2. WP2:   50.7250 N, 1.0500 W (Turn 1)
# 3. WP3:   50.7600 N, 1.0800 W (Turn 2)
# 4. End:   50.8000 N, 1.1100 W (Arrival)

cat > "$RTZ_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<route version="1.0" xmlns="http://www.cirm.org/RTZ/1/0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <routeInfo routeName="Solent Training Approach" optimizationMethod="Time" />
  <waypoints>
    <!-- Start Point -->
    <waypoint id="1" name="Pilot Station">
      <position lat="50.6920" lon="-1.0000" />
      <radius>0.5</radius>
    </waypoint>
    <!-- Turn 1 -->
    <waypoint id="2" name="Outer Approach">
      <position lat="50.7250" lon="-1.0500" />
      <radius>0.3</radius>
    </waypoint>
    <!-- Turn 2 -->
    <waypoint id="3" name="Inner Channel">
      <position lat="50.7600" lon="-1.0800" />
      <radius>0.2</radius>
    </waypoint>
    <!-- Destination -->
    <waypoint id="4" name="Berth Approach">
      <position lat="50.8000" lon="-1.1100" />
    </waypoint>
  </waypoints>
</route>
EOF

# Set ownership
chown ga:ga "$RTZ_FILE"
chmod 644 "$RTZ_FILE"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "RTZ file created at $RTZ_FILE"
echo "=== Setup complete ==="