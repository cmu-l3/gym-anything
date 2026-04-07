#!/bin/bash
set -e

echo "=== Setting up Voyage Fuel Analysis Task ==="

# Directory setup
DATA_DIR="/home/ga/Documents/VoyageData"
GT_DIR="/var/lib/bridgecommand"

mkdir -p "$DATA_DIR"
mkdir -p "$GT_DIR"

# Clean up previous runs
rm -f "$DATA_DIR/planned_route.ini"
rm -f "$DATA_DIR/engine_curve.csv"
rm -f "/home/ga/Documents/fuel_report.txt"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Python script to generate random route + engine curve AND calculate ground truth
# We do this in one script to ensure the ground truth matches the data exactly.
cat > /tmp/generate_voyage_data.py << 'EOF'
import random
import math
import json
import csv
import configparser

EARTH_RADIUS_NM = 3440.06

def haversine(lat1, lon1, lat2, lon2):
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return EARTH_RADIUS_NM * c

def generate_engine_curve():
    # Generate a cubic-like curve: Consumption = Base + k * v^3
    # Realistic values: ~15T/day at 10kts, ~40T/day at 15kts
    base = random.uniform(2.0, 4.0)
    k = random.uniform(0.008, 0.012)
    
    speeds = [6.0, 8.0, 10.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0]
    curve = []
    for s in speeds:
        cons = base + k * (s**3)
        # Add slight noise to make it not a perfect formula, requiring table lookup
        cons += random.uniform(-0.5, 0.5)
        curve.append((s, round(cons, 2)))
    return curve

def interpolate_consumption(speed, curve):
    # Find surrounding points
    sorted_curve = sorted(curve, key=lambda x: x[0])
    
    if speed <= sorted_curve[0][0]:
        return sorted_curve[0][1]
    if speed >= sorted_curve[-1][0]:
        return sorted_curve[-1][1]
        
    for i in range(len(sorted_curve)-1):
        s1, c1 = sorted_curve[i]
        s2, c2 = sorted_curve[i+1]
        if s1 <= speed <= s2:
            # Linear interpolation
            ratio = (speed - s1) / (s2 - s1)
            return c1 + ratio * (c2 - c1)
    return 0.0

def main():
    # 1. Generate Engine Curve
    curve = generate_engine_curve()
    
    with open('/home/ga/Documents/VoyageData/engine_curve.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Speed_Knots', 'Consumption_Tonnes_Per_Day'])
        writer.writerows(curve)
        
    # 2. Generate Route
    # Start somewhere in N Atlantic
    lat = random.uniform(45.0, 50.0)
    lon = random.uniform(-30.0, -20.0)
    current_speed = round(random.uniform(10.0, 15.0), 1)
    
    # Create scenario structure
    scenario_data = {
        'ship': {
            'InitialLat': lat,
            'InitialLong': lon,
            'InitialSpeed': current_speed
        },
        'legs': []
    }
    
    # Generate 3-5 legs
    num_legs = random.randint(3, 5)
    total_fuel = 0.0
    total_dist = 0.0
    ground_truth_legs = []
    
    # Current pos for iteration
    curr_lat = lat
    curr_lon = lon
    # Speed for the FIRST leg is InitialSpeed
    # Note: In Bridge Command, 'InitialSpeed' is the speed for the first segment
    # 'LegSpeed(n)' is the speed for the segment ENDING at waypoint n
    
    # Wait, let's clarify Bridge Command logic usually:
    # Ship starts at InitLat/Long with InitSpeed.
    # It travels TO LegLat(1)/LegLong(1). What speed?
    # Usually InitialSpeed is the speed of the first leg.
    # LegSpeed(1) would be the speed AFTER waypoint 1, towards waypoint 2.
    # HOWEVER, for this task, we will simplify/clarify in the task desc:
    # "LegSpeed(n) defines the speed on the way TO waypoint N." (Standard interpretation for simple waypoints)
    # Let's assume:
    # Segment 1: Start -> Waypoint 1 (Speed: InitialSpeed)
    # Segment 2: Waypoint 1 -> Waypoint 2 (Speed: LegSpeed(1))
    # ...
    
    # Actually, simpler interpretation often used in basic parsers:
    # Each leg struct has a target Lat/Long and a speed.
    # Let's generate the file such that it's unambiguous for the agent instructions.
    # We will write: "InitialSpeed is the speed for the first leg (Start -> WP1). LegSpeed(n) is the speed for the leg starting at WP(n)."
    # OR simpler: "LegSpeed(n) is the speed to reach Waypoint n." 
    # Let's stick to: "LegSpeed(n) defines the speed on the way to waypoint N."
    # BUT wait, the first leg needs a speed. That is InitialSpeed.
    
    leg_speed = current_speed
    
    for i in range(1, num_legs + 1):
        # Move randomly 2-5 degrees
        d_lat = random.uniform(-2.0, 2.0)
        d_lon = random.uniform(2.0, 5.0) # Moving generally East
        
        next_lat = curr_lat + d_lat
        next_lon = curr_lon + d_lon
        
        # Calculate distance
        dist = haversine(curr_lat, curr_lon, next_lat, next_lon)
        duration_hrs = dist / leg_speed
        duration_days = duration_hrs / 24.0
        
        # Calculate fuel
        rate = interpolate_consumption(leg_speed, curve)
        fuel = rate * duration_days
        
        total_fuel += fuel
        total_dist += dist
        
        ground_truth_legs.append({
            'segment': i,
            'start_coords': [curr_lat, curr_lon],
            'end_coords': [next_lat, next_lon],
            'speed': leg_speed,
            'distance_nm': dist,
            'duration_hrs': duration_hrs,
            'rate_tpd': rate,
            'fuel_tonnes': fuel
        })
        
        # Determine speed for NEXT leg (to be stored in THIS leg's entry for the next iteration, 
        # or simplified: The file format is usually:
        # LegLat(1)=... LegLong(1)=... LegSpeed(1)=...
        # If we say LegSpeed(n) is speed TO waypoint n, then InitialSpeed is irrelevant?
        # No, typically InitialSpeed is current state.
        # Let's standardise: 
        # Leg 1 (Start -> WP1) uses InitialSpeed.
        # Leg 2 (WP1 -> WP2) uses LegSpeed(1).
        
        # Store data for INI file
        # We need the speed for the NEXT leg to write into LegSpeed(i) if we follow "Speed AFTER WP" logic
        # OR if we follow "Speed TO WP", we write `leg_speed` into `LegSpeed(i)`?
        # Let's use the explicit instruction in README: "InitialSpeed is for Leg 1. LegSpeed(n) is for Leg n+1."
        # Actually, simpler: The file has `LegSpeed` entries. Let's just generate them and define 
        # in the description EXACTLY how to interpret them.
        # Interpretation: "Leg 1 is from Initial -> WP1 at InitialSpeed. Leg 2 is WP1 -> WP2 at LegSpeed(1)."
        
        next_speed = round(random.uniform(10.0, 16.0), 1)
        
        scenario_data['legs'].append({
            'index': i,
            'lat': next_lat,
            'long': next_lon,
            'speed_for_next_leg': next_speed # This will be LegSpeed(i)
        })
        
        # Update for next iteration
        curr_lat = next_lat
        curr_lon = next_lon
        leg_speed = next_speed

    # Write INI File
    with open('/home/ga/Documents/VoyageData/planned_route.ini', 'w') as f:
        f.write('[OwnShip]\n')
        f.write(f'InitialLat={scenario_data["ship"]["InitialLat"]:.4f}\n')
        f.write(f'InitialLong={scenario_data["ship"]["InitialLong"]:.4f}\n')
        f.write(f'InitialSpeed={scenario_data["ship"]["InitialSpeed"]:.1f}\n')
        f.write('\n')
        f.write(f'# Route Definition: Travel from Initial -> Leg 1 -> Leg 2 ...\n')
        f.write(f'# Speed Logic: InitialSpeed is for the transit to Leg 1.\n')
        f.write(f'#              LegSpeed(n) is for the transit FROM Leg n TO Leg n+1.\n')
        f.write('\n')
        
        for leg in scenario_data['legs']:
            idx = leg['index']
            f.write(f'LegLat({idx})={leg["lat"]:.4f}\n')
            f.write(f'LegLong({idx})={leg["long"]:.4f}\n')
            f.write(f'LegSpeed({idx})={leg["speed_for_next_leg"]:.1f}\n')

    # Save Ground Truth
    gt_data = {
        'total_fuel': total_fuel,
        'total_distance': total_dist,
        'num_legs': num_legs,
        'legs': ground_truth_legs
    }
    
    with open('/var/lib/bridgecommand/voyage_ground_truth.json', 'w') as f:
        json.dump(gt_data, f, indent=2)

    print(f"Generated {num_legs} legs. Total Fuel: {total_fuel:.2f}")

if __name__ == '__main__':
    main()
EOF

# Execute generation
python3 /tmp/generate_voyage_data.py

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 644 "$DATA_DIR"/*
# Secure ground truth (root only)
chmod 600 "/var/lib/bridgecommand/voyage_ground_truth.json"

# Open the directory in file manager for the agent to see
su - ga -c "DISPLAY=:1 xdg-open $DATA_DIR" &
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="