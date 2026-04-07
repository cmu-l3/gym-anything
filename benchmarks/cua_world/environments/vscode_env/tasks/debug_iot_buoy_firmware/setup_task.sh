#!/bin/bash
set -e
echo "=== Setting up Debug IoT Buoy Firmware Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create workspace
WORKSPACE_DIR="/home/ga/workspace/buoy_firmware"
sudo -u ga mkdir -p "$WORKSPACE_DIR/core"
sudo -u ga mkdir -p "$WORKSPACE_DIR/parsers"
sudo -u ga mkdir -p "$WORKSPACE_DIR/sensors"
sudo -u ga mkdir -p "$WORKSPACE_DIR/network"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# ──────────────────────────────────────────────────────────
# 1. Generate buggy Python source files
# ──────────────────────────────────────────────────────────

# core/uart_ring_buffer.py (BUG 1: Doesn't overwrite/advance tail when full)
cat > "$WORKSPACE_DIR/core/uart_ring_buffer.py" << 'EOF'
class UartRingBuffer:
    """
    Circular buffer for UART Rx data.
    If the buffer is full, pushing a new byte MUST overwrite the oldest byte
    and advance the tail pointer to maintain the exact capacity.
    """
    def __init__(self, capacity):
        self.buffer = [0] * capacity
        self.head = 0
        self.tail = 0
        self.capacity = capacity
        self.count = 0

    def push(self, byte):
        if self.count == self.capacity:
            # Buffer is full, ignore new data
            return
        self.buffer[self.head] = byte
        self.head = (self.head + 1) % self.capacity
        self.count += 1

    def get_all(self):
        """Return all bytes currently in the buffer from tail to head."""
        res = []
        curr = self.tail
        for _ in range(self.count):
            res.append(self.buffer[curr])
            curr = (curr + 1) % self.capacity
        return res
EOF

# parsers/gps_nmea.py (BUG 2: Checksum includes the '$' char)
cat > "$WORKSPACE_DIR/parsers/gps_nmea.py" << 'EOF'
def validate_checksum(sentence):
    """
    Validate NMEA 0183 checksum.
    The checksum is the bitwise XOR of all characters between '$' and '*'.
    """
    if '*' not in sentence:
        return False
    body, chk = sentence.rsplit('*', 1)
    
    calculated = 0
    # BUG: Loops over the entire body, failing to skip the leading '$'.
    for c in body:
        calculated ^= ord(c)
        
    return f"{calculated:02X}" == chk.strip()
EOF

# sensors/salinity_adc.py (BUG 3: Uses Little-Endian instead of Big-Endian)
cat > "$WORKSPACE_DIR/sensors/salinity_adc.py" << 'EOF'
import struct

def parse_salinity(high_byte, low_byte):
    """
    Parse 16-bit salinity ADC value.
    The sensor transmits the 16-bit integer in Big-Endian format.
    """
    # BUG: '<H' parses as Little-Endian. Needs to be Big-Endian.
    val = struct.unpack('<H', bytes([high_byte, low_byte]))[0]
    return val * 0.1
EOF

# sensors/temp_ds18.py (BUG 4: Two's complement logic broken)
cat > "$WORKSPACE_DIR/sensors/temp_ds18.py" << 'EOF'
def parse_temperature(raw_16bit):
    """
    Parse 12-bit two's complement temperature from the DS18 sensor.
    """
    val = raw_16bit & 0x0FFF
    # BUG: Incorrect sign extension logic. Negative values remain huge positives.
    if val & 0x0800:
        val = val  # Missing subtraction logic for 12-bit two's complement
    return val * 0.0625
EOF

# network/lora_decoder.py (BUG 5: Bitmask cuts off top nibble)
cat > "$WORKSPACE_DIR/network/lora_decoder.py" << 'EOF'
def parse_battery_voltage(raw_16bit):
    """
    Parse 12-bit battery voltage from 16-bit telemetry register.
    """
    # BUG: Masking with 0x0FF limits the value to 8 bits instead of 12 bits (0x0FFF).
    adc_val = raw_16bit & 0x0FF
    return (adc_val / 4095.0) * 4.2
EOF

# Main Simulation Script
cat > "$WORKSPACE_DIR/simulate_buoy.py" << 'EOF'
import json
import sys
from core.uart_ring_buffer import UartRingBuffer
from parsers.gps_nmea import validate_checksum
from sensors.salinity_adc import parse_salinity
from sensors.temp_ds18 import parse_temperature
from network.lora_decoder import parse_battery_voltage

def process_log(filepath):
    results = {
        "gps_valid": 0, 
        "salinity": [], 
        "temperatures": [], 
        "battery": [], 
        "buffer_state": []
    }
    
    with open(filepath, 'r') as f:
        data = json.load(f)

    # Test Ring Buffer (capacity 10)
    buffer = UartRingBuffer(10)
    for byte in data.get("uart_stream", []):
        buffer.push(byte)
    results["buffer_state"] = list(buffer.get_all())

    # Test NMEA Parsing
    for sentence in data.get("nmea_sentences", []):
        if validate_checksum(sentence):
            results["gps_valid"] += 1

    # Test Salinity (Big-Endian parsing)
    for hb, lb in data.get("salinity_raw", []):
        results["salinity"].append(parse_salinity(hb, lb))

    # Test Temperature (Two's Complement)
    for raw in data.get("temp_raw", []):
        results["temperatures"].append(parse_temperature(raw))

    # Test Battery (12-bit Mask)
    for raw in data.get("battery_raw", []):
        results["battery"].append(parse_battery_voltage(raw))

    return results

if __name__ == "__main__":
    log_path = sys.argv[1] if len(sys.argv) > 1 else "data/sample_telemetry.json"
    print(json.dumps(process_log(log_path), indent=2))
EOF

# ──────────────────────────────────────────────────────────
# 2. Generate Sample Data (Visible to Agent)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/sample_telemetry.json" << 'EOF'
{
  "uart_stream": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
  "nmea_sentences": [
    "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47"
  ],
  "salinity_raw": [
    [1, 255]
  ],
  "temp_raw": [
    4095, 
    2048, 
    100
  ],
  "battery_raw": [
    4095
  ]
}
EOF

# ──────────────────────────────────────────────────────────
# 3. Generate Hidden Ground Truth Data
# ──────────────────────────────────────────────────────────
mkdir -p /var/lib/app/ground_truth/
cat > "/var/lib/app/ground_truth/hidden_telemetry.json" << 'EOF'
{
  "uart_stream": [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150],
  "nmea_sentences": [
    "$GPRMC,225446,A,4916.45,N,12311.12,W,000.5,054.7,191194,020.3,E*68",
    "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47",
    "$GPBWC,220516,5130.02,N,00046.34,W,213.8,T,218.0,M,0004.6,N,EGLM*11",
    "$GPGLL,4916.45,N,12311.12,W,225444,A*1D"
  ],
  "salinity_raw": [
    [4, 210],
    [5, 12]
  ],
  "temp_raw": [
    4000,
    3900,
    150
  ],
  "battery_raw": [
    3500,
    3900
  ]
}
EOF
chmod 644 "/var/lib/app/ground_truth/hidden_telemetry.json"

chown -R ga:ga "$WORKSPACE_DIR"

# ──────────────────────────────────────────────────────────
# 4. Start VSCode
# ──────────────────────────────────────────────────────────
# Ensure VSCode is running
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured: $(stat -c %s /tmp/task_initial.png) bytes"
fi

echo "=== Task setup complete ==="