#!/bin/bash
set -e
echo "=== Setting up UKC Passage Planning Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create working directory
PLAN_DIR="/home/ga/Documents/PassagePlanning"
mkdir -p "$PLAN_DIR"

# 1. Create Tidal Predictions File
cat > "$PLAN_DIR/southampton_tides_20241115.txt" << 'EOF'
# Southampton (Dock Head) Tidal Predictions
# Date: 15 November 2024
# Reference: Based on UKHO published tidal harmonics
# Times in UTC, Heights in metres above Chart Datum
#
# Time_UTC  Height_m
00:30       1.2
01:00       1.0
01:30       0.9
02:00       0.8
02:30       0.7
03:00       0.7
03:30       0.8
04:00       1.0
04:30       1.4
05:00       1.9
05:30       2.5
06:00       3.1
06:30       3.6
07:00       4.0
07:30       4.2
08:00       4.3
08:30       4.2
09:00       4.1
09:30       4.0
10:00       4.1
10:30       4.2
11:00       4.3
11:30       4.2
12:00       3.9
12:30       3.5
13:00       3.0
13:30       2.5
14:00       2.0
14:30       1.6
15:00       1.3
15:30       1.1
16:00       1.0
16:30       0.9
17:00       0.9
17:30       1.0
18:00       1.3
18:30       1.7
19:00       2.3
19:30       2.9
20:00       3.4
20:30       3.8
21:00       4.1
21:30       4.2
22:00       4.2
22:30       4.1
23:00       3.9
23:30       3.5
EOF

# 2. Create Vessel Particulars File
cat > "$PLAN_DIR/vessel_particulars.txt" << 'EOF'
VESSEL PARTICULARS
==================
Name:               MT Pacific Voyager
Type:               Oil Tanker (VLCC class)
IMO Number:         9876543
LOA:                333.0 m
Beam:               60.0 m
Loaded Draft:       15.8 m (even keel)
Block Coefficient:  0.82
Max Channel Speed:  6.0 knots (port approach restriction)
EOF

# 3. Create Channel Data File
cat > "$PLAN_DIR/channel_data.txt" << 'EOF'
APPROACH CHANNEL DATA - Southampton (Thorn Channel)
====================================================
Critical Section:       Thorn Channel to Dock Head
Charted Depth (min):    14.5 m below Chart Datum
Swell Allowance:        0.3 m (based on November average)
Minimum Net UKC:        1.0 m (port authority requirement)
Squat Formula:          Barrass: Squat(m) = Cb x V^2 / 100
                        where Cb = block coefficient, V = speed in knots
EOF

# Set permissions
chown -R ga:ga "$PLAN_DIR"

# Clean up previous scenario if exists
SCENARIO_PATH="/opt/bridgecommand/Scenarios/p) Southampton Deep Draft Transit"
rm -rf "$SCENARIO_PATH" 2>/dev/null || true

# Reset bc5.ini to known state (clearing previous task changes)
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
mkdir -p "$BC_CONFIG_DIR"
cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini" 2>/dev/null || true
cp /workspace/config/bc5.ini "/opt/bridgecommand/bc5.ini" 2>/dev/null || true
chown -R ga:ga "$BC_CONFIG_DIR"

# Ensure BC is not running
pkill -f "bridgecommand" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="