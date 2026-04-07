#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug IoT Telemetry Decoder Task ==="

WORKSPACE_DIR="/home/ga/workspace/iot_telemetry"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate Realistic Binary Sensor Data (Intel Berkeley Format)
# ─────────────────────────────────────────────────────────────
echo "Generating telemetry.bin payload data..."

python3 << 'PYDATA'
import struct
import os

os.makedirs("data", exist_ok=True)
with open("data/telemetry.bin", "wb") as f:
    # Starting timestamp: 2004-02-28 00:00:00 UTC (1077926400)
    ts = 1077926400
    for i in range(5000):
        ts += 30  # 30 second intervals
        sensor_id = (i % 54) + 1
        
        # Temp: ~22.50 C -> 2250, RH: ~45.00% -> 4500
        temp_raw = 2250 + (i % 150) - 50
        rh_raw = 4000 + (i % 300)
        status = 1 if i % 100 != 0 else 0
        
        # Pack first 11 bytes: UInt32, UInt16, Int16, UInt16, UInt8
        # Format: <IHhHB
        b11 = struct.pack("<IHhHB", ts, sensor_id, temp_raw, rh_raw, status)
        
        # Calculate XOR checksum of the 11 bytes
        cksum = 0
        for b in b11:
            cksum ^= b
            
        # Append checksum byte
        payload = b11 + struct.pack("<B", cksum)
        f.write(payload)
PYDATA

chown -R ga:ga "$WORKSPACE_DIR/data"

# ─────────────────────────────────────────────────────────────
# 2. decoder.py (Bugs: Unpack Format, Checksum Loop, Scale Factor, Magnus Formula)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/decoder.py" << 'EOF'
import struct
import math

def unpack_payload(payload: bytes):
    """
    Unpacks a 12-byte sensor payload.
    Spec: UInt32 (Timestamp), UInt16 (ID), Int16 (Temp), UInt16 (RH), UInt8 (Status), UInt8 (Checksum)
    """
    if len(payload) != 12:
        return None
        
    try:
        # BUG 1: Wrong endianness and signedness for Temp (H instead of h)
        unpacked = struct.unpack(">IHHHHBB", payload)
        return {
            "timestamp": unpacked[0],
            "sensor_id": unpacked[1],
            "temp_raw": unpacked[2],
            "rh_raw": unpacked[3],
            "status": unpacked[4],
            "checksum": unpacked[5]
        }
    except struct.error:
        return None

def verify_checksum(payload: bytes) -> bool:
    """Verifies the XOR checksum (Byte 11) against Bytes 0-10."""
    calculated = 0
    # BUG 2: XORs all 12 bytes instead of just the first 11
    for b in payload:
        calculated ^= b
    return calculated == payload[11]

def calculate_dew_point(temp_c: float, rh: float) -> float:
    """Calculates dew point using the Magnus formula."""
    if rh <= 0:
        return 0.0
    
    # BUG 4: Magnus formula requires relative humidity as a fraction in the log function
    # Correct: math.log(rh / 100)
    alpha = math.log(rh) + (17.625 * temp_c) / (243.04 + temp_c)
    dew_point = (243.04 * alpha) / (17.625 - alpha)
    return dew_point

def process_payload(payload: bytes):
    """Decodes payload into physical engineering units."""
    if not verify_checksum(payload):
        return None
        
    data = unpack_payload(payload)
    if not data:
        return None

    # BUG 3: Scale factor is 0.01, but implemented as 0.1
    temp_c = data["temp_raw"] * 0.1
    rh_pct = data["rh_raw"] * 0.01
    
    dp = calculate_dew_point(temp_c, rh_pct)
    
    return {
        "timestamp": data["timestamp"],
        "sensor_id": data["sensor_id"],
        "temperature": round(temp_c, 2),
        "humidity": round(rh_pct, 2),
        "dew_point": round(dp, 2),
        "status": data["status"]
    }
EOF

# ─────────────────────────────────────────────────────────────
# 3. db_manager.py (Bug: Event-time vs Processing-time)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/db_manager.py" << 'EOF'
import sqlite3
import time

class DatabaseManager:
    def __init__(self, db_path="output.db"):
        self.conn = sqlite3.connect(db_path)
        self._create_tables()

    def _create_tables(self):
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS telemetry_hourly (
                sensor_id INTEGER,
                hour_timestamp INTEGER,
                avg_temp REAL,
                avg_rh REAL,
                avg_dp REAL,
                reading_count INTEGER,
                PRIMARY KEY (sensor_id, hour_timestamp)
            )
        """)
        self.conn.commit()

    def insert_reading(self, reading: dict):
        """Aggregates reading into hourly historical buckets."""
        
        # BUG 5: Uses current system processing time instead of the historical event timestamp
        event_time = int(time.time())
        hour_timestamp = event_time - (event_time % 3600)
        
        self.conn.execute("""
            INSERT INTO telemetry_hourly (sensor_id, hour_timestamp, avg_temp, avg_rh, avg_dp, reading_count)
            VALUES (?, ?, ?, ?, ?, 1)
            ON CONFLICT(sensor_id, hour_timestamp) DO UPDATE SET
                avg_temp = ((avg_temp * reading_count) + excluded.avg_temp) / (reading_count + 1),
                avg_rh = ((avg_rh * reading_count) + excluded.avg_rh) / (reading_count + 1),
                avg_dp = ((avg_dp * reading_count) + excluded.avg_dp) / (reading_count + 1),
                reading_count = reading_count + 1
        """, (
            reading["sensor_id"], 
            hour_timestamp, 
            reading["temperature"], 
            reading["humidity"], 
            reading["dew_point"]
        ))
        self.conn.commit()
EOF

# ─────────────────────────────────────────────────────────────
# 4. Pipeline & Tests
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
from decoder import process_payload
from db_manager import DatabaseManager
import os

def main():
    db = DatabaseManager()
    success = 0
    failed = 0
    
    with open("data/telemetry.bin", "rb") as f:
        while True:
            payload = f.read(12)
            if not payload or len(payload) < 12:
                break
                
            reading = process_payload(payload)
            if reading:
                db.insert_reading(reading)
                success += 1
            else:
                failed += 1
                
    print(f"Pipeline complete. Successfully processed: {success}, Failed: {failed}")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/tests/test_decoder.py" << 'EOF'
import struct
import pytest
import math
from decoder import unpack_payload, verify_checksum, calculate_dew_point, process_payload

def test_unpack_payload():
    # TS=1000, ID=5, Temp=-1000 (-10.00C), RH=5000 (50.00%), Status=1, CKSUM=0
    payload = struct.pack("<IHhHBB", 1000, 5, -1000, 5000, 1, 0)
    data = unpack_payload(payload)
    assert data is not None
    assert data["temp_raw"] == -1000

def test_verify_checksum():
    data = bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    cksum = 0
    for b in data: cksum ^= b
    payload = data + bytes([cksum])
    assert verify_checksum(payload) is True
    
    bad_payload = data + bytes([cksum ^ 0xFF])
    assert verify_checksum(bad_payload) is False

def test_calculate_dew_point():
    # 20.0C, 50.0% RH -> DP approx 9.27C
    dp = calculate_dew_point(20.0, 50.0)
    assert math.isclose(dp, 9.27, abs_tol=0.1)
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code pointing to the workspace
su - ga -c "code $WORKSPACE_DIR" &
sleep 5

# Wait for VS Code window
wait_for_window "Visual Studio Code" 30

# Maximize & Focus
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    wmctrl -ia "$WID"
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="