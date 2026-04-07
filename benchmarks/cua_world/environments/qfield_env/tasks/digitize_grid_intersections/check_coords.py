import sqlite3
import struct

def wkb_to_point(wkb):
    # GPKG geometry starts with a header
    # 2 bytes magic "GP", 1 byte version, 1 byte flags, int32 srs_id
    # Then the envelope (if any)
    magic, version, flags, srs_id = struct.unpack('<ccbi', wkb[0:8])
    env_indicator = (flags >> 1) & 0x07
    offset = 8
    if env_indicator == 1: offset += 32 # 4 doubles
    elif env_indicator == 2: offset += 48 # 6 doubles
    elif env_indicator == 3: offset += 48
    elif env_indicator == 4: offset += 64
    
    # WKB part
    byte_order = struct.unpack('b', wkb[offset:offset+1])[0]
    fmt = '<' if byte_order == 1 else '>'
    geom_type = struct.unpack(fmt + 'I', wkb[offset+1:offset+5])[0]
    
    if geom_type == 1: # Point
        x, y = struct.unpack(fmt + 'dd', wkb[offset+5:offset+21])
        return x, y
    return None, None

conn = sqlite3.connect('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg')
cursor = conn.cursor()
cursor.execute("SELECT name, geom FROM world_capitals WHERE name IN ('Oslo', 'Rome', 'Cape Town', 'Cairo')")
for name, geom in cursor.fetchall():
    x, y = wkb_to_point(geom)
    print(f"{name}: Lon {x:.4f}, Lat {y:.4f}")
