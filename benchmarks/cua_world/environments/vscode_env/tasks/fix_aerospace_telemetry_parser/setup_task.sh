#!/bin/bash
set -e

echo "=== Setting up Aerospace Telemetry Parser Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/telemetry_decoder"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate Hardware Interface Control Document (ICD)
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/Hardware_ICD_Spec.md" << 'EOF'
# Telemetry Avionics Interface Control Document (ICD)
**Version:** 2.1 | **Project:** Suborbital Sounding Rocket

## Packet Structure
All telemetry packets follow a standard frame format:
| Offset | Field | Length | Description |
|--------|-------|--------|-------------|
| 0      | Sync  | 1 byte | Sync byte, always `0xAA` |
| 1      | Type  | 1 byte | Payload Type (1=GPS, 2=IMU, 3=Baro, 4=Status) |
| 2      | Len   | 1 byte | Payload Length (`N` bytes) |
| 3      | Data  | `N` bytes | Payload data (see types below) |
| 3+N    | Check | 1 byte | XOR Checksum of all preceding bytes (0 to 3+N-1) |

## Payload Types

### Type 1: GPS (Length = 8)
- **Lat**: 32-bit Float (Little-Endian)
- **Lon**: 32-bit Float (Little-Endian)

### Type 2: IMU (Length = 16)
- **Sensor ID**: 8-bit Unsigned Integer
- **Padding**: 3 bytes (C-compiler 32-bit word alignment pad)
- **Accel X**: 32-bit Float (Little-Endian)
- **Accel Y**: 32-bit Float (Little-Endian)
- **Accel Z**: 32-bit Float (Little-Endian)

### Type 3: Barometer (Length = 4)
- **Pressure**: 32-bit Unsigned Integer (Little-Endian). Represents Pascals (Pa). Typical sea level is ~101325 Pa.

### Type 4: Status (Length = 1)
- **Flags**: 8-bit Bitmask
  - Bit 0 (0x01): Power Good
  - Bit 1 (0x02): Recording Active
  - Bit 2 (0x04): Igniter Continuity
  - **Bit 3 (0x08): Parachute Deployed**
EOF

# ─────────────────────────────────────────────────────────────
# 2. Generate Binary Flight Telemetry (Dynamic physical simulation)
# ─────────────────────────────────────────────────────────────
echo "Generating telemetry binary..."
python3 << 'PYGEN'
import struct

def make_packet(ptype, payload):
    pkt = bytearray([0xAA, ptype, len(payload)]) + payload
    chk = 0
    for b in pkt:
        chk ^= b
    pkt.append(chk)
    return pkt

# Simulate 1000 frames of flight data from Spaceport America
# Launch coords: 32.9903 N, -106.9750 W. Ground pressure: 86000 Pa.
with open("/home/ga/workspace/telemetry_decoder/PSAS_Launch2_Flight.tlm", "wb") as f:
    for t in range(1000):
        # 1. GPS
        lat = 32.9903 + (t * 0.000005)
        lon = -106.9750 + (t * 0.000002)
        f.write(make_packet(1, struct.pack('<ff', lat, lon)))
        
        # 2. IMU (ID=1, pad=3 bytes, ax, ay, az)
        ax = 0.01
        ay = -0.02
        az = 9.81
        if 100 < t < 250: az = 45.5 # Motor burn (high Gs)
        elif 250 <= t < 600: az = 0.0 # Coast / Freefall
        f.write(make_packet(2, struct.pack('<B3xfff', 1, ax, ay, az)))
        
        # 3. Barometer (pressure drops as altitude increases)
        pressure = int(86000 - (t * 15))
        if pressure < 1000: pressure = 1000
        f.write(make_packet(3, struct.pack('<I', pressure)))
        
        # 4. Status
        status = 0x01 | 0x02 | 0x04 # Power, Recording, Continuity
        if t > 600:
            status |= 0x08 # Parachute deployed
        f.write(make_packet(4, struct.pack('<B', status)))
PYGEN

sudo chown ga:ga "$WORKSPACE_DIR/PSAS_Launch2_Flight.tlm"

# ─────────────────────────────────────────────────────────────
# 3. Write the buggy parser script
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/parser.py" << 'EOF'
import struct
import sys
import csv
import os

def verify_checksum(packet):
    # Validates the checksum byte against the payload
    calc = sum(packet[:-1]) % 256
    return calc == packet[-1]

def parse_telemetry(filename, output_csv):
    if not os.path.exists(filename):
        print(f"File not found: {filename}")
        return

    with open(filename, 'rb') as f:
        data = f.read()

    parsed_data = []
    i = 0
    errors = 0

    while i < len(data):
        if data[i] != 0xAA:
            i += 1
            continue
        
        packet_type = data[i+1]
        length = data[i+2]
        
        # Ensure we have enough bytes for the full packet
        if i + 4 + length > len(data):
            break
            
        payload = data[i+3 : i+3+length]
        packet = data[i : i+4+length]
        
        if not verify_checksum(packet):
            errors += 1
            if errors == 1:
                print(f"Checksum mismatch at offset {i}. Parsing halted.")
                sys.exit(1)
            i += 1
            continue

        row = {'type': packet_type}
        
        if packet_type == 1: # GPS
            lat, lon = struct.unpack('>ff', payload)
            row['lat'] = lat
            row['lon'] = lon
            
        elif packet_type == 2: # IMU
            sensor_id, ax, ay, az = struct.unpack('<Bfff', payload[:13])
            row['sensor_id'] = sensor_id
            row['ax'] = ax
            row['ay'] = ay
            row['az'] = az
            
        elif packet_type == 3: # Barometer
            pressure = struct.unpack('<h', payload[:2])[0]
            row['pressure'] = pressure
            
        elif packet_type == 4: # Status
            status_byte = payload[0]
            is_deployed = bool(status_byte & 0x04)
            row['parachute_deployed'] = is_deployed
            
        parsed_data.append(row)
        i += 4 + length

    with open(output_csv, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['type', 'lat', 'lon', 'sensor_id', 'ax', 'ay', 'az', 'pressure', 'parachute_deployed'])
        writer.writeheader()
        writer.writerows(parsed_data)
    
    print(f"Successfully parsed {len(parsed_data)} frames into {output_csv}.")

if __name__ == '__main__':
    parse_telemetry('PSAS_Launch2_Flight.tlm', 'flight_trajectory.csv')
EOF

# ─────────────────────────────────────────────────────────────
# 4. Initialize Git Repo
# ─────────────────────────────────────────────────────────────
sudo -u ga bash -c '
cd /home/ga/workspace/telemetry_decoder
git init
git config user.name "Aerospace Dev"
git config user.email "dev@aerospace.local"
git add .
git commit -m "Initial commit of buggy telemetry parser"
'

# ─────────────────────────────────────────────────────────────
# 5. Launch VSCode
# ─────────────────────────────────────────────────────────────
echo "Launching VSCode..."
if ! pgrep -f "code.*telemetry_decoder" > /dev/null; then
    su - ga -c "DISPLAY=:1 code /home/ga/workspace/telemetry_decoder/parser.py &"
    sleep 5
fi

# Wait for VSCode and focus
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        echo "VSCode window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="