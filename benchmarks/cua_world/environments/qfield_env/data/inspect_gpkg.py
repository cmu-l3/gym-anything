import sqlite3
import struct
import json

def parse_gpkg_point(blob):
    if blob is None: return None, None
    try:
        flags = blob[3]
        envelope_indicator = (flags >> 1) & 0b111
        
        envelope_sizes = {0:0, 1:32, 2:48, 3:48, 4:64}
        envelope_size = envelope_sizes.get(envelope_indicator, 0)
        
        offset = 8 + envelope_size
        
        wkb_bytes = blob[offset:]
        wkb_endian_byte = wkb_bytes[0]
        is_wkb_little = (wkb_endian_byte == 1)
        endian_char = '<' if is_wkb_little else '>'
        
        x, y = struct.unpack(endian_char + 'dd', wkb_bytes[5:21])
        return y, x # lat, lon
    except Exception as e:
        return None, None

db_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get tables
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [r[0] for r in cursor.fetchall()]
print(f"Tables: {tables}")

# Get Quito, Nairobi, Singapore from world_capitals if it exists
if "world_capitals" in tables:
    cursor.execute("SELECT name, geom FROM world_capitals WHERE name IN ('Quito', 'Nairobi', 'Singapore')")
    rows = cursor.fetchall()
    for row in rows:
        lat, lon = parse_gpkg_point(row[1])
        print(f"City: {row[0]}, Lat: {lat}, Lon: {lon}")
        
    cursor.execute("SELECT COUNT(*) FROM world_capitals")
    print(f"Total capitals: {cursor.fetchone()[0]}")
    
conn.close()
