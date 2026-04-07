#!/bin/bash
set -e
echo "=== Setting up NTM Dredging Zone Setup Task ==="

# 1. Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents

# 2. Create the Notice to Mariners text file (Real-world input format)
cat > /home/ga/Documents/NTM_2024_042.txt << 'EOF'
NOTICE TO MARINERS NO. 42 OF 2024
PORT OF SOUTHAMPTON - BRAMBLE BANK - DREDGING OPERATIONS

Date: 15 October 2024
Chart Datum: WGS84

1.  Mariners are advised that dredging operations are taking place in the 
    vicinity of Bramble Bank.

2.  A temporary exclusion zone has been established bounded by the following 
    coordinates:
    
    Point A (NW Corner): 50° 47.40' N, 001° 18.00' W
    Point B (NE Corner): 50° 47.40' N, 001° 17.00' W
    Point C (SE Corner): 50° 46.80' N, 001° 17.00' W
    Point D (SW Corner): 50° 46.80' N, 001° 18.00' W

3.  The zone is marked by four Special Mark (Yellow) buoys at the corners.

4.  The Trailing Suction Hopper Dredger "MV SAND PIPER" is currently 
    operating in the center of the zone at position:
    50° 47.10' N, 001° 17.50' W

5.  The dredger is restricted in its ability to maneuver and is displaying 
    appropriate lights and shapes as per COLREGS Rule 27.

6.  Mariners are requested to navigate with caution and maintain a wide berth.

BY ORDER OF THE HARBOUR MASTER
EOF

# Set permissions
chown ga:ga /home/ga/Documents/NTM_2024_042.txt
chmod 644 /home/ga/Documents/NTM_2024_042.txt

# 3. Clean up any previous attempts
rm -rf "/opt/bridgecommand/Scenarios/NTM 42 Implementation" 2>/dev/null || true

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Ensure Bridge Command is not running
pkill -f "bridgecommand" 2>/dev/null || true

echo "=== Task Setup Complete ==="